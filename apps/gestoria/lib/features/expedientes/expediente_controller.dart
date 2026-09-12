import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/documents/documento_storage.dart';
import '../carpeta/carpeta_controller.dart';
import 'expediente_catalog.dart';

class ClienteExpedienteRow {
  const ClienteExpedienteRow({
    required this.id,
    required this.tipo,
    required this.estado,
    this.inmuebleDireccion,
  });

  final String id;
  final String tipo;
  final String estado;
  final String? inmuebleDireccion;
}

final clienteExpedientesProvider =
    FutureProvider.family<List<ClienteExpedienteRow>, String>(
        (ref, clienteId) async {
  ref.watch(authControllerProvider);
  final client = trySupabaseClient();
  final tenantId =
      ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return [];
  final rows = await client
      .from('expedientes')
      .select('id, tipo, estado, inmuebles(direccion)')
      .eq('cliente_id', clienteId)
      .eq('tenant_id', tenantId)
      .isFilter('deleted_at', null)
      .order('created_at', ascending: false);
  final out = <ClienteExpedienteRow>[];
  for (final raw in rows as List) {
    if (raw is! Map) continue;
    String? dir;
    final inm = raw['inmuebles'];
    if (inm is Map) {
      dir = '${inm['direccion'] ?? ''}'.trim();
      if (dir.isEmpty) dir = null;
    }
    out.add(
      ClienteExpedienteRow(
        id: '${raw['id']}',
        tipo: '${raw['tipo']}',
        estado: '${raw['estado'] ?? 'abierto'}',
        inmuebleDireccion: dir,
      ),
    );
  }
  return out;
});

class ThinExpedienteView {
  const ThinExpedienteView({
    required this.id,
    required this.clienteId,
    required this.tenantId,
    required this.kind,
    required this.estado,
    required this.bloque,
  });

  final String id;
  final String clienteId;
  final String tenantId;
  final ThinExpedienteKind kind;
  final String estado;
  final BloqueState bloque;
}

class ThinExpedienteController
    extends FamilyAsyncNotifier<ThinExpedienteView, String> {
  @override
  Future<ThinExpedienteView> build(String expedienteId) async {
    ref.watch(authControllerProvider);
    final client = trySupabaseClient();
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    if (client == null || tenantId == null) {
      throw StateError('not configured');
    }
    final exp = await client
        .from('expedientes')
        .select('id, cliente_id, tipo, estado')
        .eq('id', expedienteId)
        .eq('tenant_id', tenantId)
        .isFilter('deleted_at', null)
        .maybeSingle();
    if (exp == null) throw StateError('missing expediente');
    final kind = thinKindByTipo('${exp['tipo']}');
    if (kind == null) throw StateError('not thin');
    final bloqueRow = await client
        .from('bloques')
        .select('id, fields, status')
        .eq('expediente_id', expedienteId)
        .eq('template_key', kind.templateKey)
        .isFilter('deleted_at', null)
        .maybeSingle();
    if (bloqueRow == null) throw StateError('missing bloque');
    final bloqueId = '${bloqueRow['id']}';
    final docsRaw = await client
        .from('documentos')
        .select('id, tipo, storage_path, original_name')
        .eq('bloque_id', bloqueId)
        .eq('tenant_id', tenantId)
        .isFilter('deleted_at', null)
        .order('created_at');
    final documents = <CarpetaDocumento>[];
    for (final raw in docsRaw as List) {
      if (raw is! Map) continue;
      documents.add(
        CarpetaDocumento(
          id: '${raw['id']}',
          tipo: '${raw['tipo'] ?? 'other'}',
          storagePath: '${raw['storage_path'] ?? ''}',
          originalName: '${raw['original_name'] ?? ''}'.trim(),
        ),
      );
    }
    return ThinExpedienteView(
      id: '${exp['id']}',
      clienteId: '${exp['cliente_id']}',
      tenantId: tenantId,
      kind: kind,
      estado: '${exp['estado']}',
      bloque: BloqueState(
        enabled: '${bloqueRow['status']}' != 'off',
        id: bloqueId,
        values: _fields(bloqueRow['fields']),
        documents: documents,
      ),
    );
  }

  void setField(String field, String value) {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = current.bloque.copyWith(
      values: {...current.bloque.values, field: value},
    );
    state = AsyncData(
      ThinExpedienteView(
        id: current.id,
        clienteId: current.clienteId,
        tenantId: current.tenantId,
        kind: current.kind,
        estado: current.estado,
        bloque: next,
      ),
    );
  }

  Future<void> save() async {
    final current = state.valueOrNull;
    final client = trySupabaseClient();
    final bloqueId = current?.bloque.id;
    if (current == null || client == null || bloqueId == null) return;
    var status = statusOf(current.kind.template, current.bloque);
    final filed = current.bloque.values['fields.filed']?.trim() ?? '';
    if (status == BloqueUiStatus.done && filed.isEmpty) {
      status = BloqueUiStatus.watching;
    }
    if (current.kind.tipo == 'nie_tramite') {
      final st = current.bloque.values['fields.nieStatus']?.trim() ?? '';
      if (st == 'cita') {
        final cita = current.bloque.values['fields.appointment']?.trim() ?? '';
        if (cita.isEmpty) status = BloqueUiStatus.missingData;
      }
    }
    await client.from('bloques').update({
      'fields': current.bloque.values,
      'status': _dbStatus(status),
    }).eq('id', bloqueId);
    ref.invalidateSelf();
  }

  Future<void> softDelete() async {
    final current = state.valueOrNull;
    final client = trySupabaseClient();
    if (current == null || client == null) return;
    await client.from('expedientes').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', current.id).eq('tenant_id', current.tenantId);
    ref.invalidate(clienteExpedientesProvider(current.clienteId));
  }

  Future<void> attachDocument({
    required Uint8List bytes,
    required String originalName,
  }) async {
    final current = state.valueOrNull;
    final bloqueId = current?.bloque.id;
    final client = trySupabaseClient();
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (current == null || client == null || bloqueId == null) return;
    final have = {for (final d in current.bloque.documents) d.tipo};
    var tipo = 'other';
    for (final t in current.kind.requiredDocTypes) {
      if (!have.contains(t)) {
        tipo = t;
        break;
      }
    }
    final path = documentoStoragePath(
      tenantId: current.tenantId,
      clienteId: current.clienteId,
      originalName: originalName,
    );
    await uploadDocumentoBytes(
      path: path,
      bytes: bytes,
      originalName: originalName,
    );
    Map inserted;
    try {
      inserted = await client
          .from('documentos')
          .insert({
            'tenant_id': current.tenantId,
            'cliente_id': current.clienteId,
            'bloque_id': bloqueId,
            'tipo': tipo,
            'storage_path': path,
            'original_name': originalName,
            if (auth?.profile?.id != null) 'created_by': auth!.profile!.id,
          })
          .select('id')
          .single();
    } on Object {
      await rollbackDocumentoUpload(path);
      rethrow;
    }
    final next = current.bloque.copyWith(
      documents: [
        ...current.bloque.documents,
        CarpetaDocumento(
          id: '${inserted['id']}',
          tipo: tipo,
          storagePath: path,
          originalName: originalName,
        ),
      ],
    );
    var status = statusOf(current.kind.template, next);
    final filed = next.values['fields.filed']?.trim() ?? '';
    if (status == BloqueUiStatus.done && filed.isEmpty) {
      status = BloqueUiStatus.watching;
    }
    await client.from('bloques').update({
      'status': _dbStatus(status),
    }).eq('id', bloqueId);
    ref.invalidateSelf();
  }

  Future<void> removeDocument(String documentId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final client = trySupabaseClient();
    if (client == null) return;
    await client.from('documentos').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', documentId).eq('tenant_id', current.tenantId);
    ref.invalidateSelf();
  }

  Future<String?> signedUrl(String storagePath) async {
    final client = trySupabaseClient();
    if (client == null) return null;
    return client.storage.from('documentos').createSignedUrl(storagePath, 120);
  }
}

Future<void> setExpedienteEstado({
  required String expedienteId,
  required String estado,
}) async {
  final client = trySupabaseClient();
  if (client == null) throw StateError('not configured');
  await client.rpc(
    'set_expediente_estado',
    params: {
      'p_expediente_id': expedienteId,
      'p_estado': estado,
    },
  );
}

final thinExpedienteProvider = AsyncNotifierProvider.family<
    ThinExpedienteController, ThinExpedienteView, String>(
  ThinExpedienteController.new,
);

Future<String> openThinExpediente({
  required String tenantId,
  required String clienteId,
  required ThinExpedienteKind kind,
}) async {
  final client = trySupabaseClient();
  if (client == null) throw StateError('not configured');
  final exp = await client
      .from('expedientes')
      .insert({
        'tenant_id': tenantId,
        'cliente_id': clienteId,
        'tipo': kind.tipo,
        'estado': 'abierto',
      })
      .select('id')
      .single();
  final id = '${exp['id']}';
  await client.from('bloques').insert({
    'tenant_id': tenantId,
    'expediente_id': id,
    'template_key': kind.templateKey,
    'status': 'missing_data',
    'fields': <String, String>{},
  });
  return id;
}

Future<void> hideThinExpediente({
  required String tenantId,
  required String expedienteId,
}) async {
  final client = trySupabaseClient();
  if (client == null) throw StateError('not configured');
  await client.from('expedientes').update({
    'deleted_at': DateTime.now().toUtc().toIso8601String(),
  }).eq('id', expedienteId).eq('tenant_id', tenantId);
}

Map<String, String> _fields(Object? raw) {
  if (raw is! Map) return {};
  return {for (final e in raw.entries) '${e.key}': '${e.value ?? ''}'};
}

String _dbStatus(BloqueUiStatus s) {
  return switch (s) {
    BloqueUiStatus.off => 'off',
    BloqueUiStatus.missingData => 'missing_data',
    BloqueUiStatus.missingDocument => 'missing_document',
    BloqueUiStatus.watching => 'watching',
    BloqueUiStatus.done => 'done',
  };
}
