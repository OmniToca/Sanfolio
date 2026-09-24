import 'dart:async';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/documents/documento_storage.dart';
import '../../core/identity/nie_persist.dart';
import '../../core/theme/app_theme.dart';
import '../../core/money/cents.dart';
import '../../core/money/provision.dart';
import '../ai/ai_providers.dart';
import '../ai/documento_fields.dart';
import '../ai/escritura_parties.dart';
import '../ai/extract_queue.dart';
import '../ai/extract_text.dart';
import '../clientes/cliente_audit.dart';
import '../clientes/clientes_providers.dart';
import '../facturacion/facturacion_providers.dart';
import 'bloque_template.dart';
import 'documento_library.dart';
import 'stoh.dart';

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
    this.inmuebleId,
    this.contentSha256 = '',
    this.createdAt,
    this.albumKeys = const [],
    this.caption = '',
    this.aiSummary = '',
    this.aiSummaryLocale = '',
  });

  final String id;
  final String tipo;
  final String storagePath;
  final String originalName;
  final Map<String, String> extracted;
  final String? bodyText;
  final bool storagePurged;
  final String? inmuebleId;
  final String contentSha256;
  final DateTime? createdAt;
  /// template_key živých alb. Prázdné = hromada.
  final List<String> albumKeys;
  /// Ruční popis. Není extracted — AI a Guardar desky ho nemění.
  final String caption;
  /// 1–2 věty ve staff locale. Extract zapisuje; deska nemění.
  final String aiSummary;
  final String aiSummaryLocale;

  CarpetaDocumento copyWith({
    String? tipo,
    Map<String, String>? extracted,
    String? bodyText,
    bool? storagePurged,
    String? inmuebleId,
    String? contentSha256,
    DateTime? createdAt,
    List<String>? albumKeys,
    String? caption,
    String? aiSummary,
    String? aiSummaryLocale,
  }) {
    return CarpetaDocumento(
      id: id,
      tipo: tipo ?? this.tipo,
      storagePath: storagePath,
      originalName: originalName,
      extracted: extracted ?? this.extracted,
      bodyText: bodyText ?? this.bodyText,
      storagePurged: storagePurged ?? this.storagePurged,
      inmuebleId: inmuebleId ?? this.inmuebleId,
      contentSha256: contentSha256 ?? this.contentSha256,
      createdAt: createdAt ?? this.createdAt,
      albumKeys: albumKeys ?? this.albumKeys,
      caption: caption ?? this.caption,
      aiSummary: aiSummary ?? this.aiSummary,
      aiSummaryLocale: aiSummaryLocale ?? this.aiSummaryLocale,
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

/// Podíl na finca. Ne `client_contacts`.
class InmuebleTitular {
  const InmuebleTitular({
    required this.id,
    required this.nombre,
    required this.nieRaw,
    required this.lado,
    required this.cuotaBps,
    this.clienteId,
  });

  final String id;
  final String nombre;
  final String nieRaw;
  final String lado;
  final int cuotaBps;
  final String? clienteId;

  bool get isComprador => lado == 'comprador';

  InmuebleTitular copyWith({
    String? nombre,
    String? nieRaw,
    String? lado,
    int? cuotaBps,
    String? clienteId,
  }) {
    return InmuebleTitular(
      id: id,
      nombre: nombre ?? this.nombre,
      nieRaw: nieRaw ?? this.nieRaw,
      lado: lado ?? this.lado,
      cuotaBps: cuotaBps ?? this.cuotaBps,
      clienteId: clienteId ?? this.clienteId,
    );
  }
}

int compradorCuotaBpsSum(Iterable<InmuebleTitular> rows) {
  var sum = 0;
  for (final t in rows) {
    if (t.isComprador) sum += t.cuotaBps;
  }
  return sum;
}

/// 210: podíl této karty na finca, i když je prodávající (tipo 28).
String? titularSharePercentForCliente({
  required Iterable<InmuebleTitular> rows,
  required String clienteId,
  String? clienteNie,
}) {
  for (final t in rows) {
    if (t.clienteId == clienteId) return sharePercentFromBps(t.cuotaBps);
  }
  final nie = (clienteNie ?? '').trim();
  if (nie.isEmpty) return null;
  final want = normalizeNie(nie);
  for (final t in rows) {
    if (normalizeNie(t.nieRaw) == want) {
      return sharePercentFromBps(t.cuotaBps);
    }
  }
  return null;
}

/// Strana této složky. Prázdné = gestor doplní tužkou, AI neukládá.
String? folderLadoFromTitulares({
  required Iterable<InmuebleTitular> rows,
  required String clienteId,
  String? clienteNie,
  String? clienteNombre,
}) {
  for (final t in rows) {
    if (t.clienteId == clienteId) return normalizeFolderLado(t.lado);
  }
  final nie = (clienteNie ?? '').trim();
  if (nie.isNotEmpty) {
    final want = normalizeNie(nie);
    for (final t in rows) {
      if (normalizeNie(t.nieRaw) == want) {
        return normalizeFolderLado(t.lado);
      }
    }
  }
  final name = (clienteNombre ?? '').trim();
  if (name.isEmpty) return null;
  String? found;
  for (final t in rows) {
    if (t.nombre.trim().isEmpty) continue;
    if (!namesLikelyMatch(name, t.nombre)) continue;
    final lado = normalizeFolderLado(t.lado);
    if (lado == null) continue;
    if (found != null && found != lado) return null;
    found = lado;
  }
  return found;
}

String? normalizeFolderLado(String? raw) {
  final v = (raw ?? '').trim();
  if (v == 'comprador' || v == 'vendedor') return v;
  return null;
}

class CarpetaView {
  const CarpetaView({
    required this.clienteId,
    required this.tenantId,
    required this.nombre,
    required this.bloques,
    this.expedienteId,
    this.expedienteEstado = 'abierto',
    this.inmuebleId,
    this.inmuebleDireccion,
    this.inmuebleCatastral,
    this.movements = const [],
    this.titulares = const [],
    this.stohDocuments = const [],
    this.libraryDocuments = const [],
    this.inmuebles = const [],
  });

  final String clienteId;
  final String tenantId;
  final String nombre;
  final String? expedienteId;
  final String expedienteEstado;
  final String? inmuebleId;
  final String? inmuebleDireccion;
  final String? inmuebleCatastral;
  final Map<String, BloqueState> bloques;
  final List<ProvisionMovement> movements;
  final List<InmuebleTitular> titulares;
  /// Skeny ze šanonu bez alba. DNI na kartě sem nepatří.
  final List<CarpetaDocumento> stohDocuments;
  /// Celá knihovna klienta, i zařazené.
  final List<CarpetaDocumento> libraryDocuments;
  final List<LibraryInmueble> inmuebles;

  CarpetaView copyWith({
    Map<String, BloqueState>? bloques,
    String? inmuebleDireccion,
    String? inmuebleCatastral,
    List<ProvisionMovement>? movements,
    List<InmuebleTitular>? titulares,
    List<CarpetaDocumento>? stohDocuments,
    List<CarpetaDocumento>? libraryDocuments,
    List<LibraryInmueble>? inmuebles,
  }) {
    return CarpetaView(
      clienteId: clienteId,
      tenantId: tenantId,
      nombre: nombre,
      expedienteId: expedienteId,
      expedienteEstado: expedienteEstado,
      inmuebleId: inmuebleId,
      inmuebleDireccion: inmuebleDireccion ?? this.inmuebleDireccion,
      inmuebleCatastral: inmuebleCatastral ?? this.inmuebleCatastral,
      bloques: bloques ?? this.bloques,
      movements: movements ?? this.movements,
      titulares: titulares ?? this.titulares,
      stohDocuments: stohDocuments ?? this.stohDocuments,
      libraryDocuments: libraryDocuments ?? this.libraryDocuments,
      inmuebles: inmuebles ?? this.inmuebles,
    );
  }

  CarpetaView withBloque(String key, BloqueState bloque) {
    return copyWith(bloques: {...bloques, key: bloque});
  }

  CarpetaView withMovements(List<ProvisionMovement> next) {
    return copyWith(movements: next);
  }

  CarpetaView withTitulares(List<InmuebleTitular> next) {
    return copyWith(titulares: next);
  }

  /// Čip na krytu desky. Neurčeno, když karta v titulares není.
  String? folderLado({String? clienteNie}) {
    return folderLadoFromTitulares(
      rows: titulares,
      clienteId: clienteId,
      clienteNie: clienteNie ?? bloques['cliente_snapshot']?.values['fields.nie'],
      clienteNombre: nombre,
    );
  }

  CarpetaView withStoh(List<CarpetaDocumento> next) {
    return copyWith(stohDocuments: next);
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
        .select('id, nombre, apellidos, email, tel, direccion, iban, locale')
        .eq('id', clienteId)
        .eq('tenant_id', tenantId)
        .isFilter('deleted_at', null)
        .maybeSingle();
    if (persona == null) {
      throw StateError('missing cliente');
    }

    var expQuery = client
        .from('expedientes')
        .select('id, inmueble_id, estado, inmuebles(direccion, referencia_catastral)')
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
    String? inmuebleCat;
    String? inmuebleId;
    final inm = exp['inmuebles'];
    if (inm is Map) {
      inmuebleDir = '${inm['direccion'] ?? ''}'.trim();
      if (inmuebleDir.isEmpty) inmuebleDir = null;
      inmuebleCat = '${inm['referencia_catastral'] ?? ''}'.trim();
      if (inmuebleCat.isEmpty) inmuebleCat = null;
    }
    inmuebleId = '${exp['inmueble_id'] ?? ''}'.trim();
    if (inmuebleId.isEmpty || inmuebleId == 'null') inmuebleId = null;

    final rows = await client
        .from('bloques')
        .select('id, template_key, status, fields')
        .eq('expediente_id', '${exp['id']}')
        .isFilter('deleted_at', null);

    final ids = await client
        .from('client_identifiers')
        .select('kind, value_raw')
        .eq('cliente_id', clienteId)
        .isFilter('deleted_at', null);

    final snapshotValues = <String, String>{
      'fields.nie': preferredFiscalRawFromRows(ids) ?? '',
      'fields.email': '${persona['email'] ?? ''}'.trim(),
      'fields.tel': '${persona['tel'] ?? ''}'.trim(),
      'fields.address': '${persona['direccion'] ?? ''}'.trim(),
      'fields.iban': '${persona['iban'] ?? ''}'.trim(),
    };

    final docsRows = await client
        .from('documentos')
        .select(
          'id, bloque_id, tipo, storage_path, original_name, extracted, '
          'body_text, caption, ai_summary, ai_summary_locale, '
          'storage_purged_at, inmueble_id, content_sha256, created_at',
        )
        .eq('cliente_id', clienteId)
        .isFilter('deleted_at', null);

    final inmRows = await client
        .from('inmuebles')
        .select('id, direccion, referencia_catastral')
        .eq('cliente_id', clienteId)
        .isFilter('deleted_at', null);
    final inmuebles = <LibraryInmueble>[];
    for (final raw in inmRows as List) {
      if (raw is! Map) continue;
      inmuebles.add(
        LibraryInmueble(
          id: '${raw['id']}',
          direccion: '${raw['direccion'] ?? ''}'.trim(),
          catastral: '${raw['referencia_catastral'] ?? ''}'.trim(),
        ),
      );
    }

    final allExp = await client
        .from('expedientes')
        .select('id')
        .eq('cliente_id', clienteId)
        .eq('tenant_id', tenantId)
        .isFilter('deleted_at', null);
    final expIds = <String>[
      for (final raw in allExp as List)
        if (raw is Map) '${raw['id']}',
    ];
    final bloqueKeyById = <String, String>{};
    if (expIds.isNotEmpty) {
      final allBloquesRaw = await client
          .from('bloques')
          .select('id, template_key')
          .inFilter('expediente_id', expIds)
          .isFilter('deleted_at', null);
      for (final raw in allBloquesRaw as List) {
        if (raw is! Map) continue;
        bloqueKeyById['${raw['id']}'] = '${raw['template_key']}';
      }
    }

    final albumsByDoc = <String, List<String>>{};
    final placementsByDoc = <String, List<AlbumHit>>{};
    final docIds = <String>[
      for (final raw in docsRows as List)
        if (raw is Map) '${raw['id']}',
    ];
    if (docIds.isNotEmpty) {
      final placeRows = await client
          .from('documento_bloques')
          .select('documento_id, bloque_id, tipo')
          .inFilter('documento_id', docIds)
          .isFilter('deleted_at', null);
      for (final raw in placeRows as List) {
        if (raw is! Map) continue;
        final bid = '${raw['bloque_id']}';
        final key = bloqueKeyById[bid] ?? '';
        final did = '${raw['documento_id']}';
        placementsByDoc.putIfAbsent(did, () => []).add(
              AlbumHit(bloqueId: bid, tipo: '${raw['tipo'] ?? ''}'),
            );
        if (key.isEmpty) continue;
        final list = albumsByDoc.putIfAbsent(did, () => []);
        if (!list.contains(key)) list.add(key);
      }
    }

    final stohDocs = <CarpetaDocumento>[];
    final libraryDocs = <CarpetaDocumento>[];
    for (final raw in docsRows as List) {
      if (raw is! Map) continue;
      final t = transcriptFromDocumentoRow(raw);
      final id = '${raw['id']}';
      final bid = '${raw['bloque_id'] ?? ''}'.trim();
      var albums = List<String>.from(albumsByDoc[id] ?? const []);
      if (albums.isEmpty && bid.isNotEmpty && bid != 'null') {
        final k = bloqueKeyById[bid];
        if (k != null) albums = [k];
      }
      final inmRaw = '${raw['inmueble_id'] ?? ''}'.trim();
      final doc = CarpetaDocumento(
        id: id,
        tipo: '${raw['tipo']}',
        storagePath: '${raw['storage_path']}',
        originalName: '${raw['original_name'] ?? raw['tipo']}',
        extracted: t.fields,
        bodyText: t.bodyText,
        storagePurged: storagePurgedFromRow(raw),
        inmuebleId: inmRaw.isEmpty || inmRaw == 'null' ? null : inmRaw,
        contentSha256: '${raw['content_sha256'] ?? ''}'.trim(),
        createdAt: DateTime.tryParse('${raw['created_at'] ?? ''}'),
        albumKeys: albums,
        caption: '${raw['caption'] ?? ''}'.trim(),
        aiSummary: '${raw['ai_summary'] ?? ''}'.trim(),
        aiSummaryLocale: '${raw['ai_summary_locale'] ?? ''}'.trim(),
      );
      libraryDocs.add(doc);
      if (albums.isEmpty) {
        stohDocs.add(doc);
      }
    }

    final docsByBloque = documentsByAlbumBloque(
      papers: libraryDocs,
      placementsByDocId: placementsByDoc,
    );
    for (final raw in docsRows as List) {
      if (raw is! Map) continue;
      final id = '${raw['id']}';
      if (placementsByDoc.containsKey(id)) continue;
      final bid = '${raw['bloque_id'] ?? ''}'.trim();
      if (bid.isEmpty || bid == 'null') continue;
      CarpetaDocumento? paper;
      for (final d in libraryDocs) {
        if (d.id == id) {
          paper = d;
          break;
        }
      }
      if (paper == null) continue;
      docsByBloque.putIfAbsent(bid, () => []);
      if (!docsByBloque[bid]!.any((d) => d.id == id)) {
        docsByBloque[bid]!.add(paper);
      }
    }

    final bloques = <String, BloqueState>{
      for (final b in compraventaBloques) b.key: const BloqueState(enabled: false),
    };
    for (final raw in rows as List) {
      if (raw is! Map) continue;
      final key = '${raw['template_key']}';
      final values = _fieldsMap(raw['fields']);
      if (key == 'cliente_snapshot') {
        overlayClienteSnapshot(desk: values, live: snapshotValues);
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
        .select('id, kind, amount_cents, note, factura_id')
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
          facturaId: _nullIfEmpty('${raw['factura_id'] ?? ''}'),
        ),
      );
    }

    final titulares = await _fetchTitulares(inmuebleId);
    if (inmuebleId != null &&
        titulares.any(
          (t) => titularNeedsCoOwnerCard(
            isComprador: t.isComprador,
            clienteId: t.clienteId,
            nieNormalized: normalizeNie(t.nieRaw),
          ),
        )) {
      await _ensureCompradorClientes(
        inmuebleId: inmuebleId,
        tenantId: tenantId,
        folderClienteId: clienteId,
        rows: titulares,
      );
    }
    final liveTitulares = await _fetchTitulares(inmuebleId);

    return CarpetaView(
      clienteId: clienteId,
      tenantId: tenantId,
      nombre: nombre,
      expedienteId: '${exp['id']}',
      expedienteEstado: '${exp['estado'] ?? 'abierto'}',
      inmuebleId: inmuebleId,
      inmuebleDireccion: inmuebleDir,
      inmuebleCatastral: inmuebleCat,
      bloques: bloques,
      movements: movements,
      titulares: liveTitulares,
      stohDocuments: stohDocs,
      libraryDocuments: libraryDocs,
      inmuebles: inmuebles,
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
      _notice('folder.bloqueToggleError'.tr());
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
          final nieSave = await _persistCliente(_bloqueLive(key).values);
          if (nieSave.conflict) {
            _restoreSnapshotNie(nieSave.keepNie);
            _persistAgain.add(key);
            _notice(
              'folder.nieTaken'.tr(namedArgs: {'nie': nieSave.typedNie}),
            );
          }
        }
        if (key == 'escritura') {
          await _persistEscrituraFecha(
            id,
            _bloqueLive(key).values['fields.date'],
          );
        }
      } while (_persistAgain.contains(key));
    } on Object {
      _notice('folder.persistError'.tr());
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
    final auth = ref.read(authControllerProvider).valueOrNull;
    final bloque = view == null ? null : _bloqueLive(templateKey);
    final bloqueId = bloque?.id;
    if (view == null) {
      throw OfficeUploadException('not_configured');
    }
    if (bloque == null || bloqueId == null) {
      throw OfficeUploadException('bloque');
    }
    final template = _templateByKey(templateKey);
    // Bez povinných typů (KLIENT) bereme stoh nabídku — jinak always `other`.
    final tipoHints = template.requiredDocTypes.isNotEmpty
        ? template.requiredDocTypes
        : [
            for (final t in tiposForStohBloque(templateKey))
              if (t != 'other') t,
          ];
    final tipo = guessDocumentoTipo(
      requiredDocTypes: tipoHints,
      alreadyHave: {for (final d in bloque.documents) d.tipo},
      originalName: originalName,
    );
    final ingested = await ingestClienteDocumento(
      tenantId: view.tenantId,
      clienteId: view.clienteId,
      bytes: bytes,
      originalName: originalName,
      tipo: tipo,
      createdBy: auth?.profile?.id,
      inmuebleId: view.inmuebleId,
    );
    await linkDocumentoBloque(
      documentoId: ingested.id,
      bloqueId: bloqueId,
      tipo: tipo,
    );
    final existing = _libraryDoc(ingested.id);
    final placed = (existing ??
            CarpetaDocumento(
              id: ingested.id,
              tipo: ingested.tipo,
              storagePath: ingested.storagePath,
              originalName: ingested.originalName,
              contentSha256: ingested.contentSha256,
              inmuebleId: view.inmuebleId,
              createdAt: DateTime.now().toUtc(),
            ))
        .copyWith(
      tipo: tipo,
      albumKeys: {
        ...?existing?.albumKeys,
        templateKey,
      }.toList(),
      inmuebleId: existing?.inmuebleId ?? view.inmuebleId,
    );
    final already = bloque.documents.any((d) => d.id == placed.id);
    final next = bloque.copyWith(
      enabled: true,
      documents: already
          ? [
              for (final d in bloque.documents)
                if (d.id == placed.id) placed else d,
            ]
          : [...bloque.documents, placed],
    );
    state = AsyncData(
      _withLibraryPaper(view.withBloque(templateKey, next), placed),
    );
    await _persistBloque(templateKey);
    return placed;
  }

  /// Šanon bez bloku. Extract s classify. Guardar teprve zařadí.
  Future<CarpetaDocumento?> attachStohDocument({
    required Uint8List bytes,
    required String originalName,
  }) async {
    final view = state.valueOrNull;
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (view == null) {
      throw OfficeUploadException('not_configured');
    }
    final ingested = await ingestClienteDocumento(
      tenantId: view.tenantId,
      clienteId: view.clienteId,
      bytes: bytes,
      originalName: originalName,
      createdBy: auth?.profile?.id,
      rejectDuplicate: true,
    );
    final doc = CarpetaDocumento(
      id: ingested.id,
      tipo: ingested.tipo,
      storagePath: ingested.storagePath,
      originalName: ingested.originalName,
      contentSha256: ingested.contentSha256,
      createdAt: DateTime.now().toUtc(),
    );
    state = AsyncData(
      view.copyWith(
        stohDocuments: [...view.stohDocuments, doc],
        libraryDocuments: [...view.libraryDocuments, doc],
      ),
    );
    return doc;
  }

  /// Člověk zařadí papír na blok. AI sem nesmí.
  Future<bool> guardarStohDocumento({
    required String documentId,
    required String bloqueKey,
    required String tipo,
    Map<String, String> fields = const {},
    String? draftId,
  }) async {
    final view = state.valueOrNull;
    final client = trySupabaseClient();
    if (view == null || client == null) return false;
    CarpetaDocumento? doc;
    for (final d in view.stohDocuments) {
      if (d.id == documentId) {
        doc = d;
        break;
      }
    }
    doc ??= _libraryDoc(documentId);
    if (doc == null) return false;
    final current = _bloqueLive(bloqueKey);
    final plan = planStohGuardar(
      selectedBloqueKey: bloqueKey,
      selectedTipo: tipo,
      bloqueCurrentlyEnabled: current.enabled,
    );
    if (plan == null || current.id == null) return false;
    if (plan.enableBloque) {
      await setEnabled(plan.bloqueKey, true);
    }
    final live = _bloqueLive(plan.bloqueKey);
    final bloqueId = live.id;
    if (bloqueId == null) return false;
    await client.from('documentos').update({
      'bloque_id': bloqueId,
      'tipo': plan.tipo,
    }).eq('id', documentId);
    try {
      await client.rpc(
        'set_documento_placement',
        params: {
          'p_documento_id': documentId,
          'p_bloque_id': bloqueId,
          'p_tipo': plan.tipo,
          'p_on': true,
        },
      );
    } on Object {
      // Junction nesmí zhatit Guardar desky.
    }
    final yellow = extractProposalFields({
      ...doc.extracted,
      ...fields,
    });
    final guessedFinca = guessDocumentoInmueble(
      proposedBloque: plan.bloqueKey,
      properties: view.inmuebles,
      address: yellow['fields.address'] ?? '',
      catastral: yellow['fields.cadastral'] ?? '',
    );
    final placed = doc.copyWith(
      tipo: plan.tipo,
      albumKeys: {
        ...doc.albumKeys,
        plan.bloqueKey,
      }.toList(),
      extracted: yellow.isEmpty ? doc.extracted : {...doc.extracted, ...yellow},
      inmuebleId: guessedFinca ?? doc.inmuebleId,
    );
    final desk = _bloqueLive(plan.bloqueKey);
    state = AsyncData(
      _withLibraryPaper(
        (state.valueOrNull ?? view).withBloque(
          plan.bloqueKey,
          desk.copyWith(
            enabled: true,
            documents: [
              for (final d in desk.documents)
                if (d.id != documentId) d,
              placed,
            ],
          ),
        ),
        placed,
      ),
    );
    if (yellow.isNotEmpty) {
      await saveDocumentoExtracted(
        templateKey: plan.bloqueKey,
        documentId: documentId,
        fields: {
          ...doc.extracted,
          ...fields,
        },
      );
    } else {
      await _persistBloque(plan.bloqueKey);
    }
    if (guessedFinca != null && guessedFinca != (doc.inmuebleId ?? '')) {
      try {
        await client.rpc(
          'set_documento_inmueble',
          params: {
            'p_documento_id': documentId,
            'p_inmueble_id': guessedFinca,
          },
        );
      } on Object {
        // Finca je nápověda, Guardar desky bez ní platí.
      }
    }
    await discardAiDraft(draftId);
    ref.invalidateSelf();
    return true;
  }

  Future<void> discardStohDocumento({
    required String documentId,
    String? draftId,
  }) async {
    final view = state.valueOrNull;
    final client = trySupabaseClient();
    if (view == null || client == null) return;
    await client.from('documentos').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', documentId);
    await discardAiDraft(draftId);
    state = AsyncData(
      view.copyWith(
        stohDocuments: [
          for (final d in view.stohDocuments)
            if (d.id != documentId) d,
        ],
        libraryDocuments: [
          for (final d in view.libraryDocuments)
            if (d.id != documentId) d,
        ],
      ),
    );
  }

  /// Fotky v pořadí → jeden PDF. AI nespojuje.
  Future<void> mergeLibraryImages(List<String> documentIds) async {
    final view = state.valueOrNull;
    final client = trySupabaseClient();
    if (view == null || client == null) {
      throw OfficeUploadException('not_configured');
    }
    final papers = <CarpetaDocumento>[];
    for (final id in documentIds) {
      final d = _libraryDoc(id);
      if (d == null) throw OfficeUploadException('need_photos');
      papers.add(d);
    }
    final reason = libraryMergeBlockReason(
      count: papers.length,
      allImages: papers.every(
        (d) => isLibraryMergeImageName(d.originalName, d.storagePath),
      ),
    );
    if (reason != null) {
      throw OfficeUploadException(
        reason == 'stoh.mergeTooMany' ? 'too_many' : 'need_photos',
      );
    }
    final response = await client.functions.invoke(
      'merge-document-pages',
      body: {
        'tenant_id': view.tenantId,
        'cliente_id': view.clienteId,
        'documento_ids': documentIds,
      },
    );
    final data = response.data;
    if (data is! Map || data['ok'] != true) {
      final err = data is Map ? '${data['error'] ?? ''}' : '';
      throw OfficeUploadException(err.isEmpty ? 'merge' : err);
    }
    ref.invalidateSelf();
  }

  /// Album v knihovně. Desku nezapíná, pole neukládá.
  Future<bool> setLibraryPlacement({
    required String documentId,
    required String bloqueKey,
    required String tipo,
    required bool on,
  }) async {
    final view = state.valueOrNull;
    final client = trySupabaseClient();
    if (view == null || client == null) return false;
    var bloqueId = view.bloques[bloqueKey]?.id;
    final paper = _libraryDoc(documentId);
    if (paper != null &&
        (paper.inmuebleId ?? '').isNotEmpty &&
        paper.inmuebleId != view.inmuebleId) {
      bloqueId = await _bloqueIdOnInmueble(
        templateKey: bloqueKey,
        inmuebleId: paper.inmuebleId!,
      );
    }
    if (bloqueId == null || bloqueId.isEmpty) return false;
    await client.rpc(
      'set_documento_placement',
      params: {
        'p_documento_id': documentId,
        'p_bloque_id': bloqueId,
        'p_tipo': tipo.isEmpty ? paper?.tipo ?? 'other' : tipo,
        'p_on': on,
      },
    );
    ref.invalidateSelf();
    return true;
  }

  Future<bool> setLibraryInmueble({
    required String documentId,
    String? inmuebleId,
  }) async {
    final client = trySupabaseClient();
    if (client == null) return false;
    await client.rpc(
      'set_documento_inmueble',
      params: {
        'p_documento_id': documentId,
        'p_inmueble_id': inmuebleId,
      },
    );
    ref.invalidateSelf();
    return true;
  }

  /// Tužka URBANA. Bydliště na kartě klienta se nemění.
  Future<bool> updateInmuebleFinca({
    required String inmuebleId,
    required String direccion,
    String catastral = '',
  }) async {
    final dir = direccion.trim();
    if (dir.isEmpty) return false;
    final client = trySupabaseClient();
    if (client == null) return false;
    final cat = catastral.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
    await client.from('inmuebles').update({
      'direccion': dir,
      'referencia_catastral': cat.isEmpty ? null : cat,
    }).eq('id', inmuebleId);
    ref.invalidateSelf();
    return true;
  }

  /// Nová koupě z papíru na hromadě. AI finca nezakládá.
  Future<String?> addCompraventaFromFinca({
    required String direccion,
    String catastral = '',
    List<String> documentIds = const [],
  }) async {
    final view = state.valueOrNull;
    final client = trySupabaseClient();
    if (view == null || client == null) return null;
    final dir = direccion.trim();
    if (dir.isEmpty) return null;
    final expId = '${await client.rpc(
      'add_inmueble_compraventa',
      params: {'p_cliente_id': view.clienteId, 'p_direccion': dir},
    )}';
    if (expId.isEmpty || expId == 'null') return null;
    final exp = await client
        .from('expedientes')
        .select('inmueble_id')
        .eq('id', expId)
        .maybeSingle();
    final inmId = '${exp?['inmueble_id'] ?? ''}'.trim();
    if (inmId.isEmpty || inmId == 'null') return expId;
    final cat = catastral.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (cat.isNotEmpty) {
      await client.from('inmuebles').update({
        'referencia_catastral': cat,
      }).eq('id', inmId);
    }
    for (final id in documentIds) {
      await client.rpc(
        'set_documento_inmueble',
        params: {
          'p_documento_id': id,
          'p_inmueble_id': inmId,
        },
      );
    }
    ref.invalidateSelf();
    return expId;
  }

  /// Ruční popis knihovny. Extract ani Guardar desky ho nepřepíšou.
  Future<void> setDocumentoCaption({
    required String documentId,
    required String caption,
  }) async {
    final view = state.valueOrNull;
    final client = trySupabaseClient();
    if (view == null || client == null) return;
    var text = caption.trim();
    if (text.length > kLibraryCaptionMax) {
      text = text.substring(0, kLibraryCaptionMax);
    }
    await client.from('documentos').update({
      'caption': text.isEmpty ? null : text,
    }).eq('id', documentId);
    CarpetaDocumento patch(CarpetaDocumento d) =>
        d.id == documentId ? d.copyWith(caption: text) : d;
    state = AsyncData(
      view.copyWith(
        libraryDocuments: [for (final d in view.libraryDocuments) patch(d)],
        stohDocuments: [for (final d in view.stohDocuments) patch(d)],
      ),
    );
  }

  CarpetaDocumento? _libraryDoc(String id) {
    final view = state.valueOrNull;
    if (view == null) return null;
    for (final d in view.libraryDocuments) {
      if (d.id == id) return d;
    }
    for (final d in view.stohDocuments) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Po přiložení na desku: knihovna i hromada musí znát stejný papír.
  CarpetaView _withLibraryPaper(CarpetaView view, CarpetaDocumento paper) {
    final library = <CarpetaDocumento>[
      for (final d in view.libraryDocuments)
        if (d.id == paper.id) paper else d,
    ];
    if (!library.any((d) => d.id == paper.id)) {
      library.add(paper);
    }
    final pile = [
      for (final d in view.stohDocuments)
        if (d.id != paper.id) d,
    ];
    return view.copyWith(
      libraryDocuments: library,
      stohDocuments: paper.albumKeys.isEmpty ? [...pile, paper] : pile,
    );
  }

  Future<String?> _bloqueIdOnInmueble({
    required String templateKey,
    required String inmuebleId,
  }) async {
    final client = trySupabaseClient();
    final view = state.valueOrNull;
    if (client == null || view == null) return null;
    final exp = await client
        .from('expedientes')
        .select('id')
        .eq('cliente_id', view.clienteId)
        .eq('inmueble_id', inmuebleId)
        .isFilter('deleted_at', null)
        .maybeSingle();
    final expId = '${exp?['id'] ?? ''}'.trim();
    if (expId.isEmpty) return null;
    final row = await client
        .from('bloques')
        .select('id')
        .eq('expediente_id', expId)
        .eq('template_key', templateKey)
        .isFilter('deleted_at', null)
        .maybeSingle();
    final id = '${row?['id'] ?? ''}'.trim();
    return id.isEmpty ? null : id;
  }

  /// Gestor ukládá návrh z dokladu. AI sem nesmí.
  /// Vrací true, když listina nesedí ke kartě — OCR je u souboru, titulares ne.
  Future<bool> saveDocumentoExtracted({
    required String templateKey,
    required String documentId,
    required Map<String, String> fields,
  }) async {
    final view = state.valueOrNull;
    final client = trySupabaseClient();
    final bloque = view == null ? null : _bloqueLive(templateKey);
    if (view == null || client == null || bloque == null || bloque.id == null || fields.isEmpty) {
      return false;
    }
    CarpetaDocumento? currentDoc;
    for (final d in bloque.documents) {
      if (d.id == documentId) {
        currentDoc = d;
        break;
      }
    }
    final cardNie = view.bloques['cliente_snapshot']?.values['fields.nie'];
    final prepared = prepareDocumentoExtract(
      fields: fields,
      existingBody: currentDoc?.bodyText ?? '',
      currentTipo: currentDoc?.tipo,
      cardName: view.nombre,
      cardNie: cardNie,
    );
    if (prepared.isEmpty) return false;
    final aligned = prepared.fields;
    final body = prepared.body;
    final deed = prepared.deed;
    final nextTipo = prepared.nextTipo;
    final belongs = !deed ||
        deedBelongsToCliente(
          cardName: view.nombre,
          cardNie: cardNie,
          bodyText: body,
          paper: aligned,
        );
    await client.from('documentos').update({
      'extracted': aligned,
      if (prepared.bodyText != null) 'body_text': prepared.bodyText,
      if (nextTipo != null && nextTipo != currentDoc?.tipo) 'tipo': nextTipo,
    }).eq('id', documentId);
    await guardarFacturaRecibida(
      documentoId: documentId,
      fields: aligned,
      docTipo: nextTipo ?? currentDoc?.tipo,
    );
    final docs = [
      for (final d in bloque.documents)
        d.id == documentId
            ? d.copyWith(
                extracted: aligned,
                bodyText: prepared.bodyText ?? d.bodyText,
                tipo: nextTipo ?? d.tipo,
              )
            : d,
    ];
    var paper = aligned;
    if (templateKey == 'cliente_snapshot') {
      paper = lockIdentityPaper(
        paper: aligned,
        cardName: view.nombre,
        cardNie: cardNie,
      );
    }
    if (templateKey == 'suma') {
      paper = alignSumaPaperToDesk(paper);
    }
    final merged = (deed && !belongs)
        ? bloque.values
        : promotePaperToDesk(
            deskFieldKeys: _templateByKey(templateKey).fieldKeys,
            desk: bloque.values,
            paper: paper,
          );
    _draft[templateKey] = merged;
    final next = bloque.copyWith(values: merged, documents: docs);
    state = AsyncData(view.withBloque(templateKey, next));
    await _persistBloque(templateKey);
    if (deed && belongs && bloque.id != null) {
      await _persistInmuebleFromDeed(
        bloque.id!,
        paper: aligned,
        desk: merged,
      );
      await _persistTitularesFromDeed(
        bloqueId: bloque.id!,
        bodyText: body,
        tenantId: view.tenantId,
        folderClienteId: view.clienteId,
        folderNombre: view.nombre,
        folderNie: cardNie,
        deskDate: merged['fields.date'] ?? aligned['fields.date'],
      );
    }
    return deed && !belongs;
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
    await _persistInmuebleFromDeed(
      bloqueId,
      paper: const {},
      desk: {'fields.date': raw ?? ''},
    );
  }

  /// Listina drží strany a cenu. Na inmueble jde finca, notář a datum (plusvalía / 210).
  Future<void> _persistInmuebleFromDeed(
    String bloqueId, {
    required Map<String, String> paper,
    required Map<String, String> desk,
  }) async {
    final client = trySupabaseClient();
    if (client == null) return;
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
    final patch = <String, dynamic>{};
    final dateRaw =
        (desk['fields.date'] ?? paper['fields.date'] ?? '').trim();
    final parsed = DateTime.tryParse(dateRaw);
    if (parsed != null) {
      patch['escritura_fecha'] =
          '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
    }
    final notary =
        (desk['fields.notary'] ?? paper['fields.notary'] ?? '').trim();
    if (notary.isNotEmpty) patch['notario'] = notary;
    final protocol =
        (desk['fields.protocol'] ?? paper['fields.protocol'] ?? '').trim();
    if (protocol.isNotEmpty) patch['protocolo'] = protocol;
    final current = await client
        .from('inmuebles')
        .select('direccion, referencia_catastral')
        .eq('id', inmuebleId)
        .maybeSingle();
    final existingDir = '${current?['direccion'] ?? ''}'.trim();
    final existingCat = '${current?['referencia_catastral'] ?? ''}'.trim();
    final cat = (paper['fields.cadastral'] ?? '').trim();
    if (cat.isNotEmpty && existingCat.isEmpty) {
      patch['referencia_catastral'] = cat;
    }
    final addr = (paper['fields.address'] ?? '').trim();
    // Tužka / už zapsaná finca. První domicilio na listině často není URBANA.
    if (addr.isNotEmpty && existingDir.isEmpty) {
      patch['direccion'] = addr;
    }
    if (patch.isEmpty) return;
    await client.from('inmuebles').update(patch).eq('id', inmuebleId);
  }

  Future<String?> _inmuebleIdForBloque(String bloqueId) async {
    final client = trySupabaseClient();
    if (client == null) return null;
    final row = await client
        .from('bloques')
        .select('expedientes(inmueble_id)')
        .eq('id', bloqueId)
        .maybeSingle();
    final exp = row?['expedientes'];
    if (exp is! Map) return null;
    final id = '${exp['inmueble_id'] ?? ''}'.trim();
    if (id.isEmpty || id == 'null') return null;
    return id;
  }

  /// Jen když na finca ještě nikdo není. Druhý Guardar nesmí přepsat tužku.
  Future<void> _persistTitularesFromDeed({
    required String bloqueId,
    required String bodyText,
    required String tenantId,
    required String folderClienteId,
    required String folderNombre,
    String? folderNie,
    String? deskDate,
  }) async {
    final client = trySupabaseClient();
    if (client == null || !looksLikeEscrituraText(bodyText)) return;
    if (!deedBelongsToCliente(
      cardName: folderNombre,
      cardNie: folderNie,
      bodyText: bodyText,
    )) {
      return;
    }
    final proposed = proposeTitularesFromDeed(extractDeedFacts(bodyText));
    if (proposed.isEmpty) return;
    final inmuebleId = await _inmuebleIdForBloque(bloqueId);
    if (inmuebleId == null) return;
    try {
      final existing = await client
          .from('inmueble_titulares')
          .select('id')
          .eq('inmueble_id', inmuebleId)
          .isFilter('deleted_at', null)
          .limit(1);
      if (existing is List && existing.isNotEmpty) {
        await _fillEmptyTitularesFromDeed(
          inmuebleId: inmuebleId,
          proposed: proposed,
        );
        await _ensureCompradorClientes(
          inmuebleId: inmuebleId,
          tenantId: tenantId,
          folderClienteId: folderClienteId,
        );
        await _reloadTitulares(inmuebleId);
        return;
      }

      final nies = [
        for (final p in proposed)
          if (p.nieNormalized.isNotEmpty) p.nieNormalized,
      ];
      final nieToCliente = <String, String>{};
      if (nies.isNotEmpty) {
        final ids = await client
            .from('client_identifiers')
            .select('cliente_id, value_normalized')
            .eq('tenant_id', tenantId)
            .inFilter('value_normalized', nies)
            .isFilter('deleted_at', null);
        if (ids is List) {
          for (final raw in ids) {
            if (raw is! Map) continue;
            final nie = '${raw['value_normalized'] ?? ''}'.trim();
            final cid = '${raw['cliente_id'] ?? ''}'.trim();
            if (nie.isNotEmpty && cid.isNotEmpty) nieToCliente[nie] = cid;
          }
        }
      }

      String? desde;
      final parsed = DateTime.tryParse((deskDate ?? '').trim());
      if (parsed != null) {
        desde =
            '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
      }

      await client.from('inmueble_titulares').insert([
        for (final p in proposed)
          {
            'tenant_id': tenantId,
            'inmueble_id': inmuebleId,
            'lado': p.lado,
            'nombre': p.nombre,
            'nie_raw': p.nieRaw,
            'nie_normalized': p.nieNormalized,
            'cuota_bps': p.cuotaBps,
            'cliente_id': matchTitularClienteId(
              row: p,
              nieToClienteId: nieToCliente,
              folderClienteId: folderClienteId,
              folderNombre: folderNombre,
            ),
            if (desde != null) 'desde': desde,
          },
      ]);
      await _ensureCompradorClientes(
        inmuebleId: inmuebleId,
        tenantId: tenantId,
        folderClienteId: folderClienteId,
      );
      await _reloadTitulares(inmuebleId);
    } on Object {
      // Tužka musí zůstat. Unique race = druhý Guardar.
    }
  }

  /// Druhý Guardar: jen díry OCR, ne cuota ani ruční NIE.
  Future<void> _fillEmptyTitularesFromDeed({
    required String inmuebleId,
    required List<ProposedTitular> proposed,
  }) async {
    final client = trySupabaseClient();
    if (client == null) return;
    final rows = await client
        .from('inmueble_titulares')
        .select('id, lado, nombre, nie_raw, nie_normalized')
        .eq('inmueble_id', inmuebleId)
        .isFilter('deleted_at', null);
    if (rows is! List) return;
    final live = <LiveTitularRow>[
      for (final raw in rows)
        if (raw is Map)
          LiveTitularRow(
            id: '${raw['id']}',
            lado: '${raw['lado']}',
            nombre: '${raw['nombre'] ?? ''}'.trim(),
            nieNormalized: '${raw['nie_normalized'] ?? ''}'.trim(),
          ),
    ];
    final patches = planFillEmptyTitulares(
      existing: live,
      proposed: proposed,
    );
    for (final p in patches) {
      await client.from('inmueble_titulares').update({
        if (p.nieRaw != null) 'nie_raw': p.nieRaw,
        if (p.nieNormalized != null) 'nie_normalized': p.nieNormalized,
        if (p.nombre != null) 'nombre': p.nombre,
      }).eq('id', p.id);
    }
  }

  Future<List<InmuebleTitular>> _fetchTitulares(String? inmuebleId) async {
    final client = trySupabaseClient();
    if (client == null || inmuebleId == null || inmuebleId.isEmpty) {
      return const [];
    }
    try {
      final rows = await client
          .from('inmueble_titulares')
          .select('id, nombre, nie_raw, lado, cuota_bps, cliente_id')
          .eq('inmueble_id', inmuebleId)
          .isFilter('deleted_at', null)
          .order('nombre');
      final out = <InmuebleTitular>[];
      if (rows is! List) return out;
      for (final raw in rows) {
        if (raw is! Map) continue;
        final parsed = _titularFromRow(raw);
        if (parsed != null) out.add(parsed);
      }
    out.sort((a, b) {
      if (a.lado != b.lado) return a.isComprador ? -1 : 1;
      return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });
    return out;
    } on Object {
      return const [];
    }
  }

  /// Kupující s NIE dostane kartu kanceláře, ne druhou desku.
  Future<void> _ensureCompradorClientes({
    required String inmuebleId,
    required String tenantId,
    required String folderClienteId,
    List<InmuebleTitular>? rows,
  }) async {
    final client = trySupabaseClient();
    if (client == null) return;
    try {
      final folderRow = await client
          .from('clientes')
          .select('locale')
          .eq('id', folderClienteId)
          .maybeSingle();
      var locale = '${folderRow?['locale'] ?? 'cs'}'.trim();
      if (locale.isEmpty) locale = 'cs';
      final list = rows ?? await _fetchTitulares(inmuebleId);
      var changed = false;
      for (final t in list) {
        if (!titularNeedsCoOwnerCard(
          isComprador: t.isComprador,
          clienteId: t.clienteId,
          nieNormalized: normalizeNie(t.nieRaw),
        )) {
          continue;
        }
        final nie = normalizeNie(t.nieRaw);
        var clienteId = await _findClienteIdByNie(
          tenantId: tenantId,
          nieNormalized: nie,
        );
        final linkedExisting = clienteId != null;
        clienteId ??= await _insertCoOwnerCliente(
          tenantId: tenantId,
          nombre: t.nombre,
          nieRaw: t.nieRaw,
          nieNormalized: nie,
          locale: locale,
        );
        if (clienteId == null) continue;
        await client.from('inmueble_titulares').update({
          'cliente_id': clienteId,
        }).eq('id', t.id).eq('tenant_id', tenantId);
        changed = true;
        if (linkedExisting) {
          _notice('folder.coOwnerLinked'.tr());
        }
      }
      if (changed) ref.invalidate(clientesListProvider);
    } on Object {
      _notice('folder.coOwnerSaveError'.tr());
    }
  }

  Future<String?> _findClienteIdByNie({
    required String tenantId,
    required String nieNormalized,
  }) async {
    final client = trySupabaseClient();
    if (client == null || nieNormalized.isEmpty) return null;
    final hit = await client
        .from('client_identifiers')
        .select('cliente_id')
        .eq('tenant_id', tenantId)
        .eq('value_normalized', nieNormalized)
        .isFilter('deleted_at', null)
        .maybeSingle();
    final id = '${hit?['cliente_id'] ?? ''}'.trim();
    if (id.isEmpty || id == 'null') return null;
    return id;
  }

  Future<String?> _insertCoOwnerCliente({
    required String tenantId,
    required String nombre,
    required String nieRaw,
    required String nieNormalized,
    required String locale,
  }) async {
    final client = trySupabaseClient();
    if (client == null) return null;
    final inserted = await client.from('clientes').insert({
      'tenant_id': tenantId,
      'kind': 'persona',
      'nombre': nombre,
      'locale': locale,
      'status': 'activo',
    }).select('id').single();
    final id = '${inserted['id']}'.trim();
    if (id.isEmpty) return null;
    try {
      await client.from('client_identifiers').insert({
        'tenant_id': tenantId,
        'cliente_id': id,
        'kind': identifierKindFromNormalized(nieNormalized),
        'value_raw': nieRaw,
        'value_normalized': nieNormalized,
        'checksum': 'unknown',
      });
      return id;
    } on Object {
      final existing = await _findClienteIdByNie(
        tenantId: tenantId,
        nieNormalized: nieNormalized,
      );
      if (existing != null && existing != id) {
        await client.from('clientes').update({
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', id).eq('tenant_id', tenantId);
        _notice('folder.coOwnerLinked'.tr());
        return existing;
      }
      return id;
    }
  }

  InmuebleTitular? _titularFromRow(Map raw) {
    final id = '${raw['id'] ?? ''}'.trim();
    final nombre = '${raw['nombre'] ?? ''}'.trim();
    if (id.isEmpty || nombre.isEmpty) return null;
    final bps = raw['cuota_bps'];
    final cuota = bps is int
        ? bps
        : int.tryParse('$bps') ?? 0;
    if (cuota < 1) return null;
    final cliente = '${raw['cliente_id'] ?? ''}'.trim();
    return InmuebleTitular(
      id: id,
      nombre: nombre,
      nieRaw: '${raw['nie_raw'] ?? ''}'.trim(),
      lado: '${raw['lado'] ?? ''}'.trim(),
      cuotaBps: cuota,
      clienteId: cliente.isEmpty || cliente == 'null' ? null : cliente,
    );
  }

  Future<void> _reloadTitulares(String inmuebleId) async {
    final view = state.valueOrNull;
    if (view == null) return;
    final rows = await _fetchTitulares(inmuebleId);
    state = AsyncData(view.withTitulares(rows));
  }

  void _notice(String message) {
    ref.read(carpetaNoticeProvider(arg).notifier).state = message;
  }

  void setTitularShare(String titularId, String percentRaw) {
    final view = state.valueOrNull;
    if (view == null) return;
    final bps = cuotaBpsFromSharePercent(percentRaw);
    if (bps == null) return;
    state = AsyncData(
      view.withTitulares([
        for (final t in view.titulares)
          if (t.id == titularId) t.copyWith(cuotaBps: bps) else t,
      ]),
    );
    _debounce['titular:$titularId']?.cancel();
    _debounce['titular:$titularId'] = Timer(
      const Duration(milliseconds: 450),
      () {
        unawaited(_persistTitularCuota(titularId, bps));
      },
    );
  }

  void setTitularNombre(String titularId, String nombre) {
    final view = state.valueOrNull;
    if (view == null) return;
    final name = nombre.trim();
    state = AsyncData(
      view.withTitulares([
        for (final t in view.titulares)
          if (t.id == titularId) t.copyWith(nombre: nombre) else t,
      ]),
    );
    if (name.isEmpty) return;
    _debounce['titularName:$titularId']?.cancel();
    _debounce['titularName:$titularId'] = Timer(
      const Duration(milliseconds: 450),
      () {
        unawaited(_persistTitularNombre(titularId, name));
      },
    );
  }

  void setTitularNie(String titularId, String nie) {
    final view = state.valueOrNull;
    if (view == null) return;
    state = AsyncData(
      view.withTitulares([
        for (final t in view.titulares)
          if (t.id == titularId) t.copyWith(nieRaw: nie) else t,
      ]),
    );
    _debounce['titularNie:$titularId']?.cancel();
    _debounce['titularNie:$titularId'] = Timer(
      const Duration(milliseconds: 450),
      () {
        unawaited(_persistTitularNie(titularId, nie));
      },
    );
  }

  /// Tužka na šanonu. AI sem nesmí.
  Future<void> setTitularLado(String titularId, String lado) async {
    final view = state.valueOrNull;
    final next = normalizeFolderLado(lado);
    if (view == null || next == null) return;
    state = AsyncData(
      view.withTitulares([
        for (final t in view.titulares)
          if (t.id == titularId) t.copyWith(lado: next) else t,
      ]),
    );
    final client = trySupabaseClient();
    if (client == null) return;
    try {
      await client.from('inmueble_titulares').update({
        'lado': next,
      }).eq('id', titularId).eq('tenant_id', view.tenantId);
      if (next == 'comprador' && view.inmuebleId != null) {
        await _ensureCompradorClientes(
          inmuebleId: view.inmuebleId!,
          tenantId: view.tenantId,
          folderClienteId: view.clienteId,
        );
        await _reloadTitulares(view.inmuebleId!);
      }
    } on Object {
      _notice('folder.titularSaveError'.tr());
      if (view.inmuebleId != null) await _reloadTitulares(view.inmuebleId!);
    }
  }

  Future<void> _persistTitularNombre(String titularId, String nombre) async {
    final client = trySupabaseClient();
    final view = state.valueOrNull;
    if (client == null || view == null) return;
    try {
      await client.from('inmueble_titulares').update({
        'nombre': nombre,
      }).eq('id', titularId).eq('tenant_id', view.tenantId);
    } on Object {
      _notice('folder.titularSaveError'.tr());
    }
  }

  Future<void> _persistTitularNie(String titularId, String nie) async {
    final client = trySupabaseClient();
    final view = state.valueOrNull;
    final inmuebleId = view?.inmuebleId;
    if (client == null || view == null || inmuebleId == null) return;
    var normalized = nie.trim().isEmpty ? '' : normalizeNie(nie);
    if (normalized.isNotEmpty) {
      try {
        final n = await client.rpc('normalize_id', params: {'raw': nie});
        if (n != null) normalized = '$n';
      } on Object {
        normalized = normalizeNie(nie);
      }
    }
    try {
      await client.from('inmueble_titulares').update({
        'nie_raw': nie.trim(),
        'nie_normalized': normalized,
      }).eq('id', titularId).eq('tenant_id', view.tenantId);
      final row = view.titulares.where((t) => t.id == titularId);
      final isComprador = row.isEmpty ? false : row.first.isComprador;
      if (isComprador && normalized.isNotEmpty) {
        await _ensureCompradorClientes(
          inmuebleId: inmuebleId,
          tenantId: view.tenantId,
          folderClienteId: view.clienteId,
        );
        await _reloadTitulares(inmuebleId);
      }
    } on Object catch (e) {
      if (looksLikeUniqueConstraint(e)) {
        _notice('folder.titularNieTaken'.tr());
      } else {
        _notice('folder.titularSaveError'.tr());
      }
      await _reloadTitulares(inmuebleId);
    }
  }

  Future<void> _persistTitularCuota(String titularId, int cuotaBps) async {
    final client = trySupabaseClient();
    final view = state.valueOrNull;
    if (client == null || view == null) return;
    try {
      await client.from('inmueble_titulares').update({
        'cuota_bps': cuotaBps,
      }).eq('id', titularId).eq('tenant_id', view.tenantId);
    } on Object {
      _notice('folder.titularSaveError'.tr());
    }
  }

  Future<void> removeTitular(String titularId) async {
    final client = trySupabaseClient();
    final view = state.valueOrNull;
    if (client == null || view == null) return;
    try {
      await client.from('inmueble_titulares').update({
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', titularId).eq('tenant_id', view.tenantId);
      state = AsyncData(
        view.withTitulares([
          for (final t in view.titulares)
            if (t.id != titularId) t,
        ]),
      );
    } on Object {
      _notice('folder.titularSaveError'.tr());
    }
  }

  Future<void> addTitular({
    required String nombre,
    required String lado,
    required String nie,
    required String sharePercent,
  }) async {
    final client = trySupabaseClient();
    final view = state.valueOrNull;
    final inmuebleId = view?.inmuebleId;
    if (client == null || view == null || inmuebleId == null) return;
    final name = nombre.trim();
    if (name.isEmpty) throw ArgumentError('nombre');
    final side = lado.trim() == 'vendedor' ? 'vendedor' : 'comprador';
    final bps = cuotaBpsFromSharePercent(sharePercent) ?? 10000;
    var normalized = nie.trim().isEmpty ? '' : normalizeNie(nie);
    if (normalized.isNotEmpty) {
      try {
        final n = await client.rpc('normalize_id', params: {'raw': nie});
        if (n != null) normalized = '$n';
      } on Object {
        normalized = normalizeNie(nie);
      }
    }
    final inserted = await client.from('inmueble_titulares').insert({
      'tenant_id': view.tenantId,
      'inmueble_id': inmuebleId,
      'lado': side,
      'nombre': name,
      'nie_raw': nie.trim(),
      'nie_normalized': normalized,
      'cuota_bps': bps,
    }).select('id, nombre, nie_raw, lado, cuota_bps, cliente_id').single();
    final row = _titularFromRow(inserted);
    if (row == null) return;
    state = AsyncData(view.withTitulares([...view.titulares, row]));
    if (side == 'comprador') {
      await _ensureCompradorClientes(
        inmuebleId: inmuebleId,
        tenantId: view.tenantId,
        folderClienteId: view.clienteId,
      );
      await _reloadTitulares(inmuebleId);
    }
  }

  Future<({bool conflict, String keepNie, String typedNie})> _persistCliente(
    Map<String, String> values,
  ) async {
    const ok = (conflict: false, keepNie: '', typedNie: '');
    final client = trySupabaseClient();
    final view = state.valueOrNull;
    final auth = ref.read(authControllerProvider).valueOrNull;
    final tenantId = auth?.currentTenantId;
    if (client == null || view == null || tenantId == null) return ok;
    await client.from('clientes').update({
      'email': _nullIfEmpty(values['fields.email']),
      'tel': _nullIfEmpty(values['fields.tel']),
      'direccion': _nullIfEmpty(values['fields.address']),
      'iban': _nullIfEmpty(values['fields.iban']),
      if ((values['fields.nombre'] ?? '').trim().isNotEmpty)
        'nombre': values['fields.nombre']!.trim(),
    }).eq('id', view.clienteId);

    return persistClienteNie(
      client: client,
      tenantId: tenantId,
      clienteId: view.clienteId,
      nieRaw: values['fields.nie'] ?? '',
    );
  }

  void _restoreSnapshotNie(String keepNie) {
    final bloque = _bloqueLive('cliente_snapshot');
    final next = {...bloque.values, 'fields.nie': keepNie};
    _draft['cliente_snapshot'] = next;
    final view = state.valueOrNull;
    if (view == null) return;
    state = AsyncData(
      view.withBloque(
        'cliente_snapshot',
        bloque.copyWith(values: next),
      ),
    );
  }
}

/// Album desky. Tipo z junction, ne z documentos.tipo (stejný PDF ve dvou albech).
class AlbumHit {
  const AlbumHit({required this.bloqueId, this.tipo = ''});

  final String bloqueId;
  final String tipo;
}

/// Papíry na konkrétní blok této desky. Jedno album = jeden seznam, bez duplicit id.
Map<String, List<CarpetaDocumento>> documentsByAlbumBloque({
  required List<CarpetaDocumento> papers,
  required Map<String, List<AlbumHit>> placementsByDocId,
}) {
  final out = <String, List<CarpetaDocumento>>{};
  void add(String bloqueId, CarpetaDocumento doc) {
    final id = bloqueId.trim();
    if (id.isEmpty || id == 'null') return;
    final list = out.putIfAbsent(id, () => []);
    if (list.any((d) => d.id == doc.id)) return;
    list.add(doc);
  }

  for (final paper in papers) {
    final places = placementsByDocId[paper.id] ?? const <AlbumHit>[];
    if (places.isEmpty) continue;
    for (final p in places) {
      final tipo = p.tipo.trim();
      add(
        p.bloqueId,
        tipo.isNotEmpty && tipo != paper.tipo
            ? paper.copyWith(tipo: tipo)
            : paper,
      );
    }
  }
  return out;
}

/// Snackbar z persist desky (konflikt NIE). Klíč i18n už přeložený.
final carpetaNoticeProvider =
    StateProvider.family<String?, CarpetaTarget>((ref, _) => null);

final carpetaControllerProvider =
    AsyncNotifierProvider.family<CarpetaController, CarpetaView, CarpetaTarget>(
  CarpetaController.new,
);

/// Vypnutý šanon bez papírů. Chat sem nesmí posadit gestora — dům je na desce.
bool emptyOffBloque(BloqueState bloque) =>
    !bloque.enabled && bloque.documents.isEmpty;

/// Doporučené identity papíry na bloku KLIENT. Ne povinné — NIE není podmínka založení.
const kClienteSnapshotIdentityTipos = <String>['dni_nie', 'pasaporte'];

/// Má album DNI/NIE nebo pas. IBAN justificante nestačí jako identita.
bool clienteSnapshotHasIdentityPaper(Iterable<String> tipos) {
  for (final t in tipos) {
    if (t == 'dni_nie' || t == 'pasaporte') return true;
  }
  return false;
}

/// Pedir bez e-mailu i telefonu nedosáhne — stejně jako inbox `/kanal`.
bool clienteSnapshotNeedsChannel(Map<String, String> values) {
  final email = (values['fields.email'] ?? '').trim();
  final tel = (values['fields.tel'] ?? '').trim();
  return email.isEmpty && tel.isEmpty;
}

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
