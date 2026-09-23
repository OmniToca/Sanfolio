import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/documents/documento_storage.dart';
import '../../core/identity/nie_persist.dart';
import '../ai/ai_providers.dart';
import '../ai/documento_fields.dart';
import '../carpeta/carpeta_controller.dart';
import 'expediente_catalog.dart';
import 'modelo_210.dart';

/// Nemovitost klienta k výběru na tenkém spisu (210, magistrát, závěť).
class ClienteInmueblePick {
  const ClienteInmueblePick({
    required this.id,
    required this.direccion,
    this.catastral,
    this.sharePercent,
    this.lado,
  });

  final String id;
  final String direccion;
  final String? catastral;
  final String? sharePercent;
  final String? lado;
}

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
    required this.clienteNombre,
    this.clienteNie,
    this.inmuebleId,
    this.inmuebles = const [],
    this.compraventaExpedienteId,
  });

  final String id;
  final String clienteId;
  final String tenantId;
  final ThinExpedienteKind kind;
  final String estado;
  final BloqueState bloque;
  final String clienteNombre;
  final String? clienteNie;
  final String? inmuebleId;
  final List<ClienteInmueblePick> inmuebles;
  final String? compraventaExpedienteId;

  ThinExpedienteView copyWith({
    String? estado,
    BloqueState? bloque,
    String? inmuebleId,
    bool clearInmueble = false,
  }) {
    return ThinExpedienteView(
      id: id,
      clienteId: clienteId,
      tenantId: tenantId,
      kind: kind,
      estado: estado ?? this.estado,
      bloque: bloque ?? this.bloque,
      clienteNombre: clienteNombre,
      clienteNie: clienteNie,
      inmuebleId: clearInmueble ? null : (inmuebleId ?? this.inmuebleId),
      inmuebles: inmuebles,
      compraventaExpedienteId: compraventaExpedienteId,
    );
  }
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
        .select('id, cliente_id, tipo, estado, inmueble_id')
        .eq('id', expedienteId)
        .eq('tenant_id', tenantId)
        .isFilter('deleted_at', null)
        .maybeSingle();
    if (exp == null) throw StateError('missing expediente');
    final kind = thinKindByTipo('${exp['tipo']}');
    if (kind == null) throw StateError('not thin');
    final clienteId = '${exp['cliente_id']}';
    final clienteRow = await client
        .from('clientes')
        .select('nombre, apellidos')
        .eq('id', clienteId)
        .eq('tenant_id', tenantId)
        .maybeSingle();
    final clienteNombre = [
      '${clienteRow?['nombre'] ?? ''}'.trim(),
      '${clienteRow?['apellidos'] ?? ''}'.trim(),
    ].where((s) => s.isNotEmpty).join(' ');
    final idsRaw = await client
        .from('client_identifiers')
        .select('kind, value_raw')
        .eq('cliente_id', clienteId)
        .eq('tenant_id', tenantId)
        .isFilter('deleted_at', null);
    final clienteNie = preferredFiscalRawFromRows(idsRaw);
    final inmRaw = await client
        .from('inmuebles')
        .select('id, direccion, referencia_catastral')
        .eq('cliente_id', clienteId)
        .eq('tenant_id', tenantId)
        .isFilter('deleted_at', null)
        .order('created_at');
    final inmIds = <String>[];
    final inmRows = <Map>[];
    for (final raw in inmRaw as List) {
      if (raw is! Map) continue;
      final dir = '${raw['direccion'] ?? ''}'.trim();
      if (dir.isEmpty) continue;
      inmRows.add(raw);
      inmIds.add('${raw['id']}');
    }
    final shareByInmueble = await _sharePercentByInmueble(
      client: client,
      inmuebleIds: inmIds,
      clienteId: clienteId,
      clienteNie: clienteNie,
    );
    final ladoByInmueble = await _ladoByInmueble(
      client: client,
      inmuebleIds: inmIds,
      clienteId: clienteId,
      clienteNie: clienteNie,
    );
    final inmuebles = <ClienteInmueblePick>[];
    for (final raw in inmRows) {
      final id = '${raw['id']}';
      final cat = '${raw['referencia_catastral'] ?? ''}'.trim();
      inmuebles.add(
        ClienteInmueblePick(
          id: id,
          direccion: '${raw['direccion'] ?? ''}'.trim(),
          catastral: cat.isEmpty ? null : cat,
          sharePercent: shareByInmueble[id],
          lado: ladoByInmueble[id],
        ),
      );
    }
    await _mergeTitularInmuebles(
      client: client,
      tenantId: tenantId,
      clienteId: clienteId,
      clienteNie: clienteNie,
      into: inmuebles,
    );
    final compraRows = await client
        .from('expedientes')
        .select('id')
        .eq('cliente_id', clienteId)
        .eq('tenant_id', tenantId)
        .eq('tipo', 'compraventa')
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .limit(1);
    String? compraventaExpedienteId;
    if (compraRows.isNotEmpty) {
      final id = '${compraRows.first['id']}'.trim();
      if (id.isNotEmpty) compraventaExpedienteId = id;
    }
    var inmuebleId = '${exp['inmueble_id'] ?? ''}'.trim();
    if (inmuebleId.isEmpty || inmuebleId == 'null') inmuebleId = '';
    if (kind.linksInmueble && inmuebleId.isEmpty && inmuebles.length == 1) {
      inmuebleId = inmuebles.first.id;
      await client.from('expedientes').update({
        'inmueble_id': inmuebleId,
      }).eq('id', expedienteId).eq('tenant_id', tenantId);
    }
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
    var values = _fields(bloqueRow['fields']);
    if (kind.linksInmueble && inmuebleId.isNotEmpty) {
      for (final pick in inmuebles) {
        if (pick.id == inmuebleId) {
          values = withInmuebleFacts(values, pick);
          break;
        }
      }
    }
    return ThinExpedienteView(
      id: '${exp['id']}',
      clienteId: clienteId,
      tenantId: tenantId,
      kind: kind,
      estado: '${exp['estado']}',
      bloque: BloqueState(
        enabled: '${bloqueRow['status']}' != 'off',
        id: bloqueId,
        values: values,
        documents: documents,
        dbStatus: '${bloqueRow['status'] ?? 'off'}',
      ),
      clienteNombre: clienteNombre,
      clienteNie: clienteNie,
      inmuebleId: inmuebleId.isEmpty ? null : inmuebleId,
      inmuebles: inmuebles,
      compraventaExpedienteId: compraventaExpedienteId,
    );
  }

  void setField(String field, String value) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        bloque: current.bloque.copyWith(
          values: {...current.bloque.values, field: value},
        ),
      ),
    );
  }

  /// Naváže spis na inmueble. Adresu a catastral doplní, jen když na desce zejí.
  Future<void> setInmueble(String? id) async {
    final current = state.valueOrNull;
    final client = trySupabaseClient();
    if (current == null || client == null) return;
    final empty = id == null || id.isEmpty;
    ClienteInmueblePick? pick;
    if (!empty) {
      for (final item in current.inmuebles) {
        if (item.id == id) {
          pick = item;
          break;
        }
      }
    }
    var values = current.bloque.values;
    if (pick != null) values = withInmuebleFacts(values, pick);
    state = AsyncData(
      current.copyWith(
        inmuebleId: empty ? null : id,
        clearInmueble: empty,
        bloque: current.bloque.copyWith(values: values),
      ),
    );
    await client.from('expedientes').update({
      'inmueble_id': empty ? null : id,
    }).eq('id', current.id).eq('tenant_id', current.tenantId);
  }

  Future<void> save() async {
    final current = state.valueOrNull;
    final client = trySupabaseClient();
    final bloqueId = current?.bloque.id;
    if (current == null || client == null || bloqueId == null) return;
    var values = current.bloque.values;
    if (current.kind.tipo == 'impuestos_210') {
      values = applyModelo210(values);
    }
    final bloque = current.bloque.copyWith(values: values);
    var status = statusOf(current.kind.template, bloque);
    final filed = bloque.values['fields.filed']?.trim() ?? '';
    if (status == BloqueUiStatus.done && filed.isEmpty) {
      status = BloqueUiStatus.watching;
    }
    if (current.kind.tipo == 'nie_tramite' ||
        current.kind.tipo == 'policia' ||
        current.kind.tipo == 'ayuntamiento' ||
        current.kind.tipo == 'testament') {
      final st = (bloque.values['fields.nieStatus'] ??
              bloque.values['fields.tramiteStatus'])
          ?.trim() ??
          '';
      if (st == 'cita') {
        final cita = bloque.values['fields.appointment']?.trim() ?? '';
        if (cita.isEmpty) status = BloqueUiStatus.missingData;
      }
    }
    await client.from('bloques').update({
      'fields': values,
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
    String? tipo,
  }) async {
    final current = state.valueOrNull;
    final bloqueId = current?.bloque.id;
    final client = trySupabaseClient();
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (current == null || client == null || bloqueId == null) return;
    final have = {for (final d in current.bloque.documents) d.tipo};
    final slots = current.kind.paperSlotTypes;
    final resolved = (tipo != null && tipo.isNotEmpty)
        ? tipo
        : guessDocumentoTipo(
            requiredDocTypes: slots.isEmpty ? const ['other'] : slots,
            alreadyHave: have,
            originalName: originalName,
          );
    final ingested = await ingestClienteDocumento(
      tenantId: current.tenantId,
      clienteId: current.clienteId,
      bytes: bytes,
      originalName: originalName,
      tipo: resolved,
      createdBy: auth?.profile?.id,
    );
    await linkDocumentoBloque(
      documentoId: ingested.id,
      bloqueId: bloqueId,
      tipo: resolved,
    );
    final next = current.bloque.copyWith(
      documents: [
        ...current.bloque.documents,
        CarpetaDocumento(
          id: ingested.id,
          tipo: resolved,
          storagePath: ingested.storagePath,
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
    startExtractInBackground(
      tenantId: current.tenantId,
      clienteId: current.clienteId,
      storagePath: ingested.storagePath,
      mime: mimeForOfficeFile(originalName),
      docTipo: resolved,
      bloqueKey: current.kind.templateKey,
    );
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

Map<String, String> withInmuebleFacts(
  Map<String, String> values,
  ClienteInmueblePick pick,
) {
  final next = Map<String, String>.from(values);
  if ((next['fields.address'] ?? '').trim().isEmpty) {
    next['fields.address'] = pick.direccion;
  }
  final cat = pick.catastral?.trim() ?? '';
  if ((next['fields.cadastral'] ?? '').trim().isEmpty && cat.isNotEmpty) {
    next['fields.cadastral'] = cat;
  }
  final share = pick.sharePercent?.trim() ?? '';
  if ((next['fields.sharePercent'] ?? '').trim().isEmpty && share.isNotEmpty) {
    next['fields.sharePercent'] = share;
  }
  if ((next['fields.incomeKind'] ?? '').trim().isEmpty) {
    final kind = proposeIncomeKindFromFolderLado(pick.lado);
    if (kind != null) next['fields.incomeKind'] = kind;
  }
  return next;
}

Future<Map<String, String>> _sharePercentByInmueble({
  required dynamic client,
  required List<String> inmuebleIds,
  required String clienteId,
  String? clienteNie,
}) async {
  if (inmuebleIds.isEmpty) return {};
  try {
    final rows = await client
        .from('inmueble_titulares')
        .select(
          'id, inmueble_id, nombre, nie_raw, lado, cuota_bps, cliente_id',
        )
        .inFilter('inmueble_id', inmuebleIds)
        .isFilter('deleted_at', null);
    final byInm = <String, List<InmuebleTitular>>{};
    if (rows is List) {
      for (final raw in rows) {
        if (raw is! Map) continue;
        final inm = '${raw['inmueble_id'] ?? ''}'.trim();
        final id = '${raw['id'] ?? ''}'.trim();
        final nombre = '${raw['nombre'] ?? ''}'.trim();
        final bps = raw['cuota_bps'];
        final cuota = bps is int ? bps : int.tryParse('$bps') ?? 0;
        if (inm.isEmpty || id.isEmpty || nombre.isEmpty || cuota < 1) continue;
        final cid = '${raw['cliente_id'] ?? ''}'.trim();
        byInm.putIfAbsent(inm, () => []).add(
              InmuebleTitular(
                id: id,
                nombre: nombre,
                nieRaw: '${raw['nie_raw'] ?? ''}'.trim(),
                lado: '${raw['lado'] ?? ''}'.trim(),
                cuotaBps: cuota,
                clienteId: cid.isEmpty || cid == 'null' ? null : cid,
              ),
            );
      }
    }
    final out = <String, String>{};
    for (final e in byInm.entries) {
      final share = titularSharePercentForCliente(
        rows: e.value,
        clienteId: clienteId,
        clienteNie: clienteNie,
      );
      if (share != null) out[e.key] = share;
    }
    return out;
  } on Object {
    return {};
  }
}

Future<Map<String, String>> _ladoByInmueble({
  required dynamic client,
  required List<String> inmuebleIds,
  required String clienteId,
  String? clienteNie,
}) async {
  if (inmuebleIds.isEmpty) return {};
  try {
    final rows = await client
        .from('inmueble_titulares')
        .select(
          'id, inmueble_id, nombre, nie_raw, lado, cuota_bps, cliente_id',
        )
        .inFilter('inmueble_id', inmuebleIds)
        .isFilter('deleted_at', null);
    final byInm = <String, List<InmuebleTitular>>{};
    if (rows is List) {
      for (final raw in rows) {
        if (raw is! Map) continue;
        final inm = '${raw['inmueble_id'] ?? ''}'.trim();
        final id = '${raw['id'] ?? ''}'.trim();
        final nombre = '${raw['nombre'] ?? ''}'.trim();
        final bps = raw['cuota_bps'];
        final cuota = bps is int ? bps : int.tryParse('$bps') ?? 0;
        if (inm.isEmpty || id.isEmpty) continue;
        final cid = '${raw['cliente_id'] ?? ''}'.trim();
        byInm.putIfAbsent(inm, () => []).add(
              InmuebleTitular(
                id: id,
                nombre: nombre,
                nieRaw: '${raw['nie_raw'] ?? ''}'.trim(),
                lado: '${raw['lado'] ?? ''}'.trim(),
                cuotaBps: cuota < 1 ? 1 : cuota,
                clienteId: cid.isEmpty || cid == 'null' ? null : cid,
              ),
            );
      }
    }
    final out = <String, String>{};
    for (final e in byInm.entries) {
      final lado = folderLadoFromTitulares(
        rows: e.value,
        clienteId: clienteId,
        clienteNie: clienteNie,
      );
      if (lado != null) out[e.key] = lado;
    }
    return out;
  } on Object {
    return {};
  }
}

Future<void> _mergeTitularInmuebles({
  required dynamic client,
  required String tenantId,
  required String clienteId,
  String? clienteNie,
  required List<ClienteInmueblePick> into,
}) async {
  try {
    final tit = await client
        .from('inmueble_titulares')
        .select('inmueble_id')
        .eq('cliente_id', clienteId)
        .eq('lado', 'comprador')
        .isFilter('deleted_at', null);
    final have = {for (final p in into) p.id};
    final extraIds = <String>[];
    if (tit is List) {
      for (final raw in tit) {
        if (raw is! Map) continue;
        final id = '${raw['inmueble_id'] ?? ''}'.trim();
        if (id.isEmpty || have.contains(id)) continue;
        extraIds.add(id);
        have.add(id);
      }
    }
    if (extraIds.isEmpty) return;
    final inmRaw = await client
        .from('inmuebles')
        .select('id, direccion, referencia_catastral')
        .eq('tenant_id', tenantId)
        .inFilter('id', extraIds)
        .isFilter('deleted_at', null);
    final share = await _sharePercentByInmueble(
      client: client,
      inmuebleIds: extraIds,
      clienteId: clienteId,
      clienteNie: clienteNie,
    );
    final lado = await _ladoByInmueble(
      client: client,
      inmuebleIds: extraIds,
      clienteId: clienteId,
      clienteNie: clienteNie,
    );
    if (inmRaw is! List) return;
    for (final raw in inmRaw) {
      if (raw is! Map) continue;
      final id = '${raw['id']}';
      final dir = '${raw['direccion'] ?? ''}'.trim();
      if (dir.isEmpty) continue;
      final cat = '${raw['referencia_catastral'] ?? ''}'.trim();
      into.add(
        ClienteInmueblePick(
          id: id,
          direccion: dir,
          catastral: cat.isEmpty ? null : cat,
          sharePercent: share[id],
          lado: lado[id],
        ),
      );
    }
  } on Object {
    return;
  }
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
