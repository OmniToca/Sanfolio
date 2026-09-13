import 'dart:async';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/documents/documento_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/money/cents.dart';
import '../../core/money/provision.dart';
import '../ai/documento_fields.dart';
import '../ai/extract_text.dart';
import '../clientes/cliente_audit.dart';
import 'bloque_template.dart';

enum BloqueUiStatus { off, missingData, missingDocument, watching, done }

class CarpetaDocumento {
  const CarpetaDocumento({
    required this.id,
    required this.tipo,
    required this.storagePath,
    required this.originalName,
    this.extracted = const {},
    this.bodyText,
    this.storagePurged = false,
  });

  final String id;
  final String tipo;
  final String storagePath;
  final String originalName;
  final Map<String, String> extracted;
  final String? bodyText;
  final bool storagePurged;

  CarpetaDocumento copyWith({
    Map<String, String>? extracted,
    String? bodyText,
    bool? storagePurged,
  }) {
    return CarpetaDocumento(
      id: id,
      tipo: tipo,
      storagePath: storagePath,
      originalName: originalName,
      extracted: extracted ?? this.extracted,
      bodyText: bodyText ?? this.bodyText,
      storagePurged: storagePurged ?? this.storagePurged,
    );
  }
}

class BloqueState {
  const BloqueState({
    required this.enabled,
    this.id,
    this.values = const {},
    this.documents = const [],
    this.dbStatus = 'off',
  });

  final String? id;
  final bool enabled;
  final Map<String, String> values;
  final List<CarpetaDocumento> documents;
  /// Stav z Postgres. Flutter ho nepočítá do DB.
  final String dbStatus;

  BloqueState copyWith({
    bool? enabled,
    String? id,
    Map<String, String>? values,
    List<CarpetaDocumento>? documents,
    String? dbStatus,
  }) {
    return BloqueState(
      enabled: enabled ?? this.enabled,
      id: id ?? this.id,
      values: values ?? this.values,
      documents: documents ?? this.documents,
      dbStatus: dbStatus ?? this.dbStatus,
    );
  }
}

class CarpetaView {
  const CarpetaView({
    required this.clienteId,
    required this.tenantId,
    required this.nombre,
    required this.bloques,
    this.expedienteId,
    this.expedienteEstado = 'abierto',
    this.inmuebleDireccion,
    this.movements = const [],
  });

  final String clienteId;
  final String tenantId;
  final String nombre;
  final String? expedienteId;
  final String expedienteEstado;
  final String? inmuebleDireccion;
  final Map<String, BloqueState> bloques;
  final List<ProvisionMovement> movements;

  CarpetaView withBloque(String key, BloqueState bloque) {
    return CarpetaView(
      clienteId: clienteId,
      tenantId: tenantId,
      nombre: nombre,
      expedienteId: expedienteId,
      expedienteEstado: expedienteEstado,
      inmuebleDireccion: inmuebleDireccion,
      bloques: {...bloques, key: bloque},
      movements: movements,
    );
  }

  CarpetaView withMovements(List<ProvisionMovement> next) {
    return CarpetaView(
      clienteId: clienteId,
      tenantId: tenantId,
      nombre: nombre,
      expedienteId: expedienteId,
      expedienteEstado: expedienteEstado,
      inmuebleDireccion: inmuebleDireccion,
      bloques: bloques,
      movements: next,
    );
  }
}

/// Klíč desky: klient + konkrétní koupě. Bez exp = nejnovější compraventa.
class CarpetaTarget {
  const CarpetaTarget({required this.clienteId, this.expedienteId});

  final String clienteId;
  final String? expedienteId;

  @override
  bool operator ==(Object other) =>
      other is CarpetaTarget &&
      other.clienteId == clienteId &&
      other.expedienteId == expedienteId;

  @override
  int get hashCode => Object.hash(clienteId, expedienteId);
}

/// Tužka na desce. Stav bloků je v `bloques`; kontakt na `clientes`.
class CarpetaController extends FamilyAsyncNotifier<CarpetaView, CarpetaTarget> {
  final _debounce = <String, Timer>{};
  /// Rozepsaná pole, dokud neproběhne persist. Nesmí jít do Riverpod hned —
  /// rebuild celé desky na webu maže TextField.
  final _draft = <String, Map<String, String>>{};
  final _persisting = <String>{};
  final _persistAgain = <String>{};

  @override
  Future<CarpetaView> build(CarpetaTarget target) async {
    ref.onDispose(() {
      for (final t in _debounce.values) {
        t.cancel();
      }
    });
    final client = trySupabaseClient();
    if (client == null) {
      throw StateError('not configured');
    }
    final auth = await ref.watch(authControllerProvider.future);
    final tenantId = auth.currentTenantId;
    if (tenantId == null) {
      throw StateError('no tenant');
    }
    final clienteId = target.clienteId;

    final persona = await client
        .from('clientes')
        .select('id, nombre, apellidos, email, tel, direccion, iban')
        .eq('id', clienteId)
        .eq('tenant_id', tenantId)
        .isFilter('deleted_at', null)
        .maybeSingle();
    if (persona == null) {
      throw StateError('missing cliente');
    }

    var expQuery = client
        .from('expedientes')
        .select('id, inmueble_id, estado, inmuebles(direccion)')
        .eq('cliente_id', clienteId)
        .eq('tipo', 'compraventa')
        .eq('tenant_id', tenantId)
        .isFilter('deleted_at', null);
    final wanted = target.expedienteId;
    if (wanted != null && wanted.isNotEmpty) {
      expQuery = expQuery.eq('id', wanted);
    }
    final exp = await expQuery
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (exp == null) {
      throw StateError('missing expediente');
    }
    String? inmuebleDir;
    final inm = exp['inmuebles'];
    if (inm is Map) {
      inmuebleDir = '${inm['direccion'] ?? ''}'.trim();
      if (inmuebleDir.isEmpty) inmuebleDir = null;
    }

    final rows = await client
        .from('bloques')
        .select('id, template_key, status, fields')
        .eq('expediente_id', '${exp['id']}')
        .isFilter('deleted_at', null);

    final ids = await client
        .from('client_identifiers')
        .select('value_raw')
        .eq('cliente_id', clienteId)
        .isFilter('deleted_at', null)
        .limit(1)
        .maybeSingle();

    final snapshotValues = <String, String>{
      'fields.nie': '${ids?['value_raw'] ?? ''}'.trim(),
      'fields.email': '${persona['email'] ?? ''}'.trim(),
      'fields.tel': '${persona['tel'] ?? ''}'.trim(),
      'fields.address': '${persona['direccion'] ?? ''}'.trim(),
      'fields.iban': '${persona['iban'] ?? ''}'.trim(),
    };

    final docsRows = await client
        .from('documentos')
        .select(
          'id, bloque_id, tipo, storage_path, original_name, extracted, '
          'body_text, storage_purged_at',
        )
        .eq('cliente_id', clienteId)
        .isFilter('deleted_at', null);
    final docsByBloque = <String, List<CarpetaDocumento>>{};
    for (final raw in docsRows as List) {
      if (raw is! Map) continue;
      final bid = '${raw['bloque_id']}';
      docsByBloque.putIfAbsent(bid, () => []).add(
            () {
              final t = transcriptFromDocumentoRow(raw);
              return CarpetaDocumento(
                id: '${raw['id']}',
                tipo: '${raw['tipo']}',
                storagePath: '${raw['storage_path']}',
                originalName: '${raw['original_name'] ?? raw['tipo']}',
                extracted: t.fields,
                bodyText: t.bodyText,
                storagePurged: storagePurgedFromRow(raw),
              );
            }(),
          );
    }

    final bloques = <String, BloqueState>{
      for (final b in compraventaBloques) b.key: const BloqueState(enabled: false),
    };
    for (final raw in rows as List) {
      if (raw is! Map) continue;
      final key = '${raw['template_key']}';
      final values = _fieldsMap(raw['fields']);
      if (key == 'cliente_snapshot') {
        values.addAll({
          for (final e in snapshotValues.entries)
            if (e.value.isNotEmpty) e.key: e.value,
        });
      }
      final bid = '${raw['id']}';
      bloques[key] = BloqueState(
        id: bid,
        enabled: '${raw['status']}' != 'off',
        values: values,
        documents: docsByBloque[bid] ?? const [],
        dbStatus: '${raw['status'] ?? 'off'}',
      );
    }

    final nombre = [
      '${persona['nombre'] ?? ''}'.trim(),
      '${persona['apellidos'] ?? ''}'.trim(),
    ].where((s) => s.isNotEmpty).join(' ');

    await auditClienteOpen(
      clienteId: clienteId,
      tenantId: tenantId,
      surface: 'carpeta',
    );

    final movRows = await client
        .from('provision_movements')
        .select('id, kind, amount_cents, note')
        .eq('expediente_id', '${exp['id']}')
        .isFilter('deleted_at', null)
        .order('created_at');
    final movements = <ProvisionMovement>[];
    for (final raw in movRows as List) {
      if (raw is! Map) continue;
      movements.add(
        ProvisionMovement(
          id: '${raw['id']}',
          kind: '${raw['kind']}',
          amountCents: centsFromStored('${raw['amount_cents']}'),
          note: _nullIfEmpty('${raw['note'] ?? ''}'),
        ),
      );
    }

    return CarpetaView(
      clienteId: clienteId,
      tenantId: tenantId,
      nombre: nombre,
      expedienteId: '${exp['id']}',
      expedienteEstado: '${exp['estado'] ?? 'abierto'}',
      inmuebleDireccion: inmuebleDir,
      bloques: bloques,
      movements: movements,
    );
  }

  /// Tužka v poli má přednost před posledním stavem z provideru.
  BloqueState _bloqueLive(String key) {
    final stored =
        state.valueOrNull?.bloques[key] ?? const BloqueState(enabled: false);
    final draft = _draft[key];
    if (draft == null) return stored;
    return stored.copyWith(enabled: true, values: draft);
  }

  Future<void> setEnabled(String key, bool enabled, {String? reason}) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final bloque = _bloqueLive(key);
    final id = bloque.id;
    final client = trySupabaseClient();
    if (client == null || id == null) return;
    if (!enabled && (reason == null || reason.trim().isEmpty)) {
      throw ArgumentError('reason');
    }
    try {
      final status = await client.rpc(
        'override_bloque_status',
        params: {
          'p_bloque_id': id,
          'p_enabled': enabled,
          'p_reason': reason,
        },
      );
      final db = '$status';
      final next = bloque.copyWith(
        enabled: enabled,
        dbStatus: db.isEmpty ? (enabled ? 'missing_data' : 'off') : db,
      );
      state = AsyncData(current.withBloque(key, next));
    } on Object {
      // Tužka musí zůstat viditelná i když RPC spadne.
    }
  }

  void setField(String key, String field, String value) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (key == 'provision_factura') {
      // Přijato / vyúčtováno se needituje — jen pohyby.
      return;
    }
    final bloque = _bloqueLive(key);
    // Nevolat state = … tady: Flutter web při rebuildu celé desky maže input.
    _draft[key] = {...bloque.values, field: value};
    _debounce[key]?.cancel();
    _debounce[key] = Timer(const Duration(milliseconds: 450), () {
      unawaited(_persistBloque(key));
    });
  }

  Future<void> _persistBloque(String key) async {
    if (_persisting.contains(key)) {
      _persistAgain.add(key);
      return;
    }
    final client = trySupabaseClient();
    final id = _bloqueLive(key).id;
    if (client == null || id == null) return;
    _persisting.add(key);
    try {
      do {
        _persistAgain.remove(key);
        final bloque = _bloqueLive(key);
        await client.from('bloques').update({
          'fields': bloque.values,
        }).eq('id', id);
        final status = await client.rpc(
          'recompute_bloque_status',
          params: {'p_bloque_id': id},
        );
        final view = state.valueOrNull;
        final live = _bloqueLive(key);
        if (view != null) {
          // Jen chip z RPC. Hodnoty z aktuální tužky, ne ze snímku před await.
          state = AsyncData(
            view.withBloque(
              key,
              live.copyWith(
                dbStatus: status == null ? live.dbStatus : '$status',
              ),
            ),
          );
        }
        if (!_mapsEqual(live.values, bloque.values)) {
          _persistAgain.add(key);
        }
        if (!_persistAgain.contains(key)) {
          _draft.remove(key);
        }
        if (key == 'cliente_snapshot') {
          await _persistCliente(_bloqueLive(key).values);
        }
        if (key == 'escritura') {
          await _persistEscrituraFecha(
            id,
            _bloqueLive(key).values['fields.date'],
          );
        }
      } while (_persistAgain.contains(key));
    } on Object {
      // Tužka musí zůstat použitelná i když jeden zápis spadne.
    } finally {
      _persisting.remove(key);
    }
  }

  bool _mapsEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  Future<CarpetaDocumento?> attachDocument({
    required String templateKey,
    required Uint8List bytes,
    required String originalName,
  }) async {
    try {
      return await _attachDocument(
        templateKey: templateKey,
        bytes: bytes,
        originalName: originalName,
      );
    } on OfficeUploadException {
      rethrow;
    } on Object catch (e) {
      debugPrint('attachDocument $e');
      throw OfficeUploadException(_shortAttachCode(e));
    }
  }

  Future<CarpetaDocumento?> _attachDocument({
    required String templateKey,
    required Uint8List bytes,
    required String originalName,
  }) async {
    final view = state.valueOrNull;
    final client = trySupabaseClient();
    final auth = ref.read(authControllerProvider).valueOrNull;
    final bloque = view == null ? null : _bloqueLive(templateKey);
    final bloqueId = bloque?.id;
    if (view == null || client == null) {
      throw OfficeUploadException('not_configured');
    }
    if (bloque == null || bloqueId == null) {
      throw OfficeUploadException('bloque');
    }
    final template = _templateByKey(templateKey);
    final tipo = guessDocumentoTipo(
      requiredDocTypes: template.requiredDocTypes,
      alreadyHave: {for (final d in bloque.documents) d.tipo},
      originalName: originalName,
    );
    final path = documentoStoragePath(
      tenantId: view.tenantId,
      clienteId: view.clienteId,
      originalName: originalName,
      bloqueId: bloqueId,
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
            'tenant_id': view.tenantId,
            'cliente_id': view.clienteId,
            'bloque_id': bloqueId,
            'tipo': tipo,
            'storage_path': path,
            'original_name': originalName,
            if (auth?.profile?.id != null) 'created_by': auth!.profile!.id,
          })
          .select('id')
          .single();
    } on Object catch (e) {
      debugPrint('documentos insert $e');
      await rollbackDocumentoUpload(path);
      throw OfficeUploadException('db');
    }
    final doc = CarpetaDocumento(
      id: '${inserted['id']}',
      tipo: tipo,
      storagePath: path,
      originalName: originalName,
    );
    final next = bloque.copyWith(
      enabled: true,
      documents: [...bloque.documents, doc],
    );
    state = AsyncData(view.withBloque(templateKey, next));
    await _persistBloque(templateKey);
    return doc;
  }

  /// Gestor ukládá návrh z dokladu. AI sem nesmí.
  Future<void> saveDocumentoExtracted({
    required String templateKey,
    required String documentId,
    required Map<String, String> fields,
  }) async {
    final view = state.valueOrNull;
    final client = trySupabaseClient();
    final bloque = view == null ? null : _bloqueLive(templateKey);
    if (view == null || client == null || bloque == null || bloque.id == null || fields.isEmpty) {
      return;
    }
    final t = splitDocumentoTranscript(fields);
    if (t.fields.isEmpty && t.bodyText == null) return;
    await client.from('documentos').update({
      'extracted': t.fields,
      if (t.bodyText != null) 'body_text': t.bodyText,
    }).eq('id', documentId);
    final docs = [
      for (final d in bloque.documents)
        d.id == documentId
            ? d.copyWith(extracted: t.fields, bodyText: t.bodyText)
            : d,
    ];
    final merged = promotePaperToDesk(
      deskFieldKeys: _templateByKey(templateKey).fieldKeys,
      desk: bloque.values,
      paper: t.fields,
    );
    _draft[templateKey] = merged;
    final next = bloque.copyWith(values: merged, documents: docs);
    state = AsyncData(view.withBloque(templateKey, next));
    await _persistBloque(templateKey);
  }

  Future<void> removeDocument(String templateKey, String documentId) async {
    final view = state.valueOrNull;
    final client = trySupabaseClient();
    final bloque = view == null ? null : _bloqueLive(templateKey);
    if (view == null || client == null || bloque == null || bloque.id == null) {
      return;
    }
    await client.from('documentos').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', documentId);
    final next = bloque.copyWith(
      documents: bloque.documents.where((d) => d.id != documentId).toList(),
    );
    state = AsyncData(view.withBloque(templateKey, next));
    await _persistBloque(templateKey);
  }

  Future<void> addProvisionMovement({
    required String kind,
    required int amountCents,
    String? note,
  }) async {
    final view = state.valueOrNull;
    final client = trySupabaseClient();
    final expId = view?.expedienteId;
    if (view == null || client == null || expId == null) return;
    if (!provisionKinds.contains(kind) || amountCents == 0) return;
    await client.from('provision_movements').insert({
      'tenant_id': view.tenantId,
      'expediente_id': expId,
      'kind': kind,
      'amount_cents': amountCents,
      'note': _nullIfEmpty(note),
    });
    ref.invalidateSelf();
  }

  Future<void> removeProvisionMovement(String movementId) async {
    final view = state.valueOrNull;
    final client = trySupabaseClient();
    if (view == null || client == null) return;
    await client.from('provision_movements').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', movementId).eq('tenant_id', view.tenantId);
    ref.invalidateSelf();
  }

  Future<String?> signedUrl(String storagePath) async {
    final client = trySupabaseClient();
    if (client == null) return null;
    return client.storage.from('documentos').createSignedUrl(storagePath, 120);
  }

  Future<void> _persistEscrituraFecha(String bloqueId, String? raw) async {
    final client = trySupabaseClient();
    if (client == null) return;
    final parsed = DateTime.tryParse((raw ?? '').trim());
    if (parsed == null) return;
    final row = await client
        .from('bloques')
        .select('expedientes(inmueble_id)')
        .eq('id', bloqueId)
        .maybeSingle();
    final exp = row?['expedientes'];
    String? inmuebleId;
    if (exp is Map) inmuebleId = '${exp['inmueble_id'] ?? ''}';
    if (inmuebleId == null || inmuebleId.isEmpty || inmuebleId == 'null') {
      return;
    }
    final day =
        '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
    await client.from('inmuebles').update({'escritura_fecha': day}).eq('id', inmuebleId);
  }

  Future<void> _persistCliente(Map<String, String> values) async {
    final client = trySupabaseClient();
    final view = state.valueOrNull;
    final auth = ref.read(authControllerProvider).valueOrNull;
    final tenantId = auth?.currentTenantId;
    if (client == null || view == null || tenantId == null) return;
    await client.from('clientes').update({
      'email': _nullIfEmpty(values['fields.email']),
      'tel': _nullIfEmpty(values['fields.tel']),
      'direccion': _nullIfEmpty(values['fields.address']),
      'iban': _nullIfEmpty(values['fields.iban']),
      if ((values['fields.nombre'] ?? '').trim().isNotEmpty)
        'nombre': values['fields.nombre']!.trim(),
    }).eq('id', view.clienteId);

    final nie = (values['fields.nie'] ?? '').trim();
    final existing = await client
        .from('client_identifiers')
        .select('id')
        .eq('cliente_id', view.clienteId)
        .isFilter('deleted_at', null)
        .maybeSingle();
    if (nie.isEmpty) {
      if (existing != null) {
        await client.from('client_identifiers').update({
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', existing['id']);
      }
      return;
    }
    var normalized = nie.toUpperCase();
    try {
      final n = await client.rpc('normalize_id', params: {'raw': nie});
      if (n != null) normalized = '$n';
    } on Object {
      normalized = nie.toUpperCase().replaceAll(RegExp(r'[\s\-\./]'), '');
    }
    if (existing != null) {
      await client.from('client_identifiers').update({
        'value_raw': nie,
        'value_normalized': normalized,
      }).eq('id', existing['id']);
    } else {
      await client.from('client_identifiers').insert({
        'tenant_id': tenantId,
        'cliente_id': view.clienteId,
        'kind': 'nie',
        'value_raw': nie,
        'value_normalized': normalized,
        'checksum': 'unknown',
      });
    }
  }
}

final carpetaControllerProvider =
    AsyncNotifierProvider.family<CarpetaController, CarpetaView, CarpetaTarget>(
  CarpetaController.new,
);

BloqueUiStatus statusOf(BloqueTemplate template, BloqueState bloque) {
  if (!bloque.enabled) return BloqueUiStatus.off;
  final missing = template.requiredKeys.where((f) {
    final v = bloque.values[f];
    return v == null || v.trim().isEmpty;
  });
  if (missing.isNotEmpty) return BloqueUiStatus.missingData;
  final have = {for (final d in bloque.documents) d.tipo};
  if (template.requiredDocTypes.isNotEmpty) {
    if (template.requiredDocsMode == RequiredDocsMode.any) {
      if (!template.requiredDocTypes.any(have.contains)) {
        return BloqueUiStatus.missingDocument;
      }
    } else if (template.requiredDocTypes.any((t) => !have.contains(t))) {
      return BloqueUiStatus.missingDocument;
    }
  }
  return BloqueUiStatus.done;
}

/// Chip na desce bere serverový stav, ne lokální odhad.
BloqueUiStatus bloqueUiStatus(String dbStatus) {
  return switch (dbStatus) {
    'missing_data' => BloqueUiStatus.missingData,
    'missing_document' => BloqueUiStatus.missingDocument,
    'watching' => BloqueUiStatus.watching,
    'done' => BloqueUiStatus.done,
    _ => BloqueUiStatus.off,
  };
}

String statusLabel(BloqueUiStatus s) {
  return switch (s) {
    BloqueUiStatus.off => 'blockStatus.off'.tr(),
    BloqueUiStatus.missingData => 'blockStatus.missingData'.tr(),
    BloqueUiStatus.missingDocument => 'blockStatus.missingDocument'.tr(),
    BloqueUiStatus.watching => 'blockStatus.watching'.tr(),
    BloqueUiStatus.done => 'blockStatus.done'.tr(),
  };
}

/// Pozadí chipu. Zelená jen Hotovo — zapnutý blok s dírou nesmí vypadat OK.
Color bloqueStatusFill(BloqueUiStatus s) {
  return switch (s) {
    BloqueUiStatus.off => AppTheme.chipOff,
    BloqueUiStatus.missingData => AppTheme.statusWarnSoft,
    BloqueUiStatus.missingDocument => AppTheme.statusAlertSoft,
    BloqueUiStatus.watching => AppTheme.statusWatchSoft,
    BloqueUiStatus.done => AppTheme.statusOkSoft,
  };
}

Color bloqueStatusInk(BloqueUiStatus s) {
  return switch (s) {
    BloqueUiStatus.off => AppTheme.pencil,
    BloqueUiStatus.missingData => AppTheme.statusWarn,
    BloqueUiStatus.missingDocument => AppTheme.statusAlert,
    BloqueUiStatus.watching => AppTheme.statusWatch,
    BloqueUiStatus.done => AppTheme.statusOk,
  };
}

/// Papíry na krytu. Stav chipu dál z RPC, tady jen poctivý text (ne 2/3 u any).
class BloqueDocsHint {
  const BloqueDocsHint({
    required this.mode,
    required this.satisfied,
    required this.missingTypes,
    required this.showBar,
    required this.barValue,
  });

  final RequiredDocsMode mode;
  final bool satisfied;
  final List<String> missingTypes;
  final bool showBar;
  final double barValue;
}

BloqueDocsHint? bloqueDocsHint(BloqueTemplate template, BloqueState bloque) {
  if (template.requiredDocTypes.isEmpty) return null;
  final have = {for (final d in bloque.documents) d.tipo};
  if (template.requiredDocsMode == RequiredDocsMode.any) {
    return BloqueDocsHint(
      mode: RequiredDocsMode.any,
      satisfied: template.requiredDocTypes.any(have.contains),
      missingTypes: const [],
      showBar: false,
      barValue: 0,
    );
  }
  final missing = [
    for (final t in template.requiredDocTypes)
      if (!have.contains(t)) t,
  ];
  final total = template.requiredDocTypes.length;
  final filled = total - missing.length;
  return BloqueDocsHint(
    mode: RequiredDocsMode.all,
    satisfied: missing.isEmpty,
    missingTypes: missing,
    showBar: total >= 2 && missing.isNotEmpty,
    barValue: total == 0 ? 0 : filled / total,
  );
}

Map<String, String> _fieldsMap(Object? raw) {
  if (raw is! Map) return {};
  return {
    for (final e in raw.entries) '${e.key}': '${e.value ?? ''}',
  };
}

String? _nullIfEmpty(String? v) {
  final t = v?.trim() ?? '';
  return t.isEmpty ? null : t;
}

BloqueTemplate _templateByKey(String key) {
  for (final b in compraventaBloques) {
    if (b.key == key) return b;
  }
  return BloqueTemplate(key: key, fieldKeys: const []);
}

String _shortAttachCode(Object error) {
  final raw = error.toString().replaceAll('\n', ' ');
  if (raw.length <= 40) return raw;
  return raw.substring(0, 40);
}
