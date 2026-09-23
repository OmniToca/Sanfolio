import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/documents/documento_storage.dart';
import '../../core/identity/legal_hold.dart';
import '../../core/identity/nie_persist.dart';
import '../ai/ai_providers.dart';
import '../ai/escritura_parties.dart';
import '../ai/extract_text.dart';
import '../carpeta/carpeta_controller.dart';
import '../facturacion/facturacion_providers.dart';
import '../settings/office_settings_controller.dart';
import 'cliente_audit.dart';
import 'clientes_providers.dart';
import 'poder_glance.dart';

class ClienteContact {
  const ClienteContact({
    required this.id,
    required this.nombre,
    required this.locale,
    this.relacion,
    this.tel,
    this.email,
  });

  final String id;
  final String nombre;
  final String locale;
  final String? relacion;
  final String? tel;
  final String? email;
}

class ClienteDocumento {
  const ClienteDocumento({
    required this.id,
    required this.tipo,
    required this.storagePath,
    required this.originalName,
    this.extracted = const {},
    this.bodyText,
    this.storagePurged = false,
    this.bloqueId,
  });

  final String id;
  final String tipo;
  final String storagePath;
  final String originalName;
  final Map<String, String> extracted;
  final String? bodyText;
  final bool storagePurged;
  /// Papír ze složky (ESCRITURA, voda…). Na kartě žijí jen doklady bez bloku.
  final String? bloqueId;

  bool get fromDesk => (bloqueId ?? '').isNotEmpty;

  ClienteDocumento copyWith({
    Map<String, String>? extracted,
    String? bodyText,
    bool? storagePurged,
    String? bloqueId,
  }) {
    return ClienteDocumento(
      id: id,
      tipo: tipo,
      storagePath: storagePath,
      originalName: originalName,
      extracted: extracted ?? this.extracted,
      bodyText: bodyText ?? this.bodyText,
      storagePurged: storagePurged ?? this.storagePurged,
      bloqueId: bloqueId ?? this.bloqueId,
    );
  }
}

/// Koš na kartě: schované s originálem z karty i ze složky. Vysypané zmizí z UI.
List<ClienteDocumento> trashVisibleOnCard(List<ClienteDocumento> hidden) {
  return [
    for (final d in hidden.reversed)
      if (!d.storagePurged) d,
  ];
}

/// Živý papír na kartě — ne schovaný a nevisí na bloku desky.
bool isClienteCardLiveDoc({required Object? deletedAt, required Object? bloqueId}) {
  if (deletedAt != null) return false;
  final b = '$bloqueId'.trim();
  return b.isEmpty || b == 'null';
}

/// Typy papírů na kartě, ne na desce. Úřední názvy se nepřekládají pryč.
const clienteCardDocTypes = <String>['dni_nie', 'pasaporte'];

/// Karta klienta: kontakt, stav, druhá osoba. Složka je vedle, ne tady.
class ClienteCard {
  const ClienteCard({
    required this.id,
    required this.tenantId,
    required this.nombre,
    required this.locale,
    required this.status,
    required this.deleted,
    this.email,
    this.tel,
    this.iban,
    this.notas,
    this.nie,
    this.contacts = const [],
    this.documents = const [],
    this.hiddenDocuments = const [],
    this.coOwnerFolderId,
    this.coOwnerFolderNombre,
    this.coOwnerDireccion,
    this.coOwnerExpedienteId,
    this.holds = const [],
    this.erasureRequested = false,
    this.poder = PoderGlance.missing,
  });

  final String id;
  final String tenantId;
  final String nombre;
  final String locale;
  final String status;
  final bool deleted;
  final String? email;
  final String? tel;
  final String? iban;
  final String? notas;
  final String? nie;
  final List<ClienteContact> contacts;
  final List<ClienteDocumento> documents;
  final List<ClienteDocumento> hiddenDocuments;
  final String? coOwnerFolderId;
  final String? coOwnerFolderNombre;
  final String? coOwnerDireccion;
  final String? coOwnerExpedienteId;
  final List<ClienteHold> holds;
  final bool erasureRequested;
  final PoderGlance poder;

  bool get isCoOwnerOnly => (coOwnerFolderId ?? '').isNotEmpty;

  bool clienteHoldActive(DateTime today) {
    for (final h in holds) {
      if ((h.documentoId ?? '').isNotEmpty) continue;
      if (legalHoldBlocks(until: h.until, today: today)) return true;
    }
    return false;
  }

  bool documentoHoldActive(String documentoId, DateTime today) {
    for (final h in holds) {
      if (holdCoversDocumento(
        until: h.until,
        holdDocumentoId: h.documentoId,
        documentoId: documentoId,
        today: today,
      )) {
        return true;
      }
    }
    return false;
  }

  DateTime? get clienteHoldUntil {
    DateTime? latest;
    for (final h in holds) {
      if ((h.documentoId ?? '').isNotEmpty) continue;
      if (latest == null || h.until.isAfter(latest)) latest = h.until;
    }
    return latest;
  }
}

/// Řádek `legal_holds`. `documentoId` null = celá karta.
class ClienteHold {
  const ClienteHold({
    required this.id,
    required this.until,
    this.reason,
    this.documentoId,
  });

  final String id;
  final DateTime until;
  final String? reason;
  final String? documentoId;
}

class ClienteCardController extends FamilyAsyncNotifier<ClienteCard, String> {
  @override
  Future<ClienteCard> build(String clienteId) async {
    ref.watch(authControllerProvider);
    final client = trySupabaseClient();
    final auth = await ref.watch(authControllerProvider.future);
    final tenantId = auth.currentTenantId;
    if (client == null || tenantId == null) {
      throw StateError('not configured');
    }

    final row = await client
        .from('clientes')
        .select(
          'id, nombre, apellidos, email, tel, iban, locale, status, notas, '
          'deleted_at, erasure_requested_at, '
          'client_identifiers(kind, value_raw, deleted_at)',
        )
        .eq('id', clienteId)
        .eq('tenant_id', tenantId)
        .maybeSingle();
    if (row == null) {
      throw StateError('missing cliente');
    }

    final contactsRaw = await client
        .from('client_contacts')
        .select('id, nombre, relacion, tel, email, locale')
        .eq('cliente_id', clienteId)
        .eq('tenant_id', tenantId)
        .isFilter('deleted_at', null)
        .order('created_at');

    final contacts = <ClienteContact>[];
    for (final raw in contactsRaw as List) {
      if (raw is! Map) continue;
      contacts.add(
        ClienteContact(
          id: '${raw['id']}',
          nombre: '${raw['nombre'] ?? ''}'.trim(),
          relacion: _trimOrNull(raw['relacion']),
          tel: _trimOrNull(raw['tel']),
          email: _trimOrNull(raw['email']),
          locale: '${raw['locale'] ?? 'cs'}',
        ),
      );
    }

    final nombre = [
      '${row['nombre'] ?? ''}'.trim(),
      '${row['apellidos'] ?? ''}'.trim(),
    ].where((s) => s.isNotEmpty).join(' ');

    final nie = preferredFiscalRawFromRows(row['client_identifiers']);

    final docsRaw = await client
        .from('documentos')
        .select(
          'id, tipo, storage_path, original_name, extracted, body_text, '
          'storage_purged_at, deleted_at, bloque_id',
        )
        .eq('cliente_id', clienteId)
        .eq('tenant_id', tenantId)
        .order('created_at');

    final documents = <ClienteDocumento>[];
    final hidden = <ClienteDocumento>[];
    for (final raw in docsRaw as List) {
      if (raw is! Map) continue;
      final doc = _clienteDocumentoFromRow(raw);
      if (raw['deleted_at'] != null) {
        hidden.add(doc);
      } else if (isClienteCardLiveDoc(
        deletedAt: raw['deleted_at'],
        bloqueId: raw['bloque_id'],
      )) {
        documents.add(doc);
      }
    }

    final coOwner = await _coOwnerFolderFor(
      client: client,
      tenantId: tenantId,
      clienteId: clienteId,
    );

    final docIds = [
      for (final d in documents) d.id,
      for (final d in hidden) d.id,
    ];
    final holds = await _loadHolds(
      client: client,
      tenantId: tenantId,
      clienteId: clienteId,
      documentoIds: docIds,
    );

    var poder = PoderGlance.missing;
    try {
      final powerHits = await client.rpc(
        'cliente_poder_glance',
        params: {
          'p_tenant_id': tenantId,
          'p_cliente_ids': [clienteId],
        },
      );
      if (powerHits is List && powerHits.isNotEmpty && powerHits.first is Map) {
        poder = poderGlanceFromRpc(
          raw: Map<String, dynamic>.from(powerHits.first as Map),
          today: DateTime.now(),
          warnDays:
              ref.watch(officeSettingsProvider).valueOrNull?.poderWarnDays ?? 60,
        );
      }
    } on Object {
      // Přehled nesmí shodit kartu.
    }

    return ClienteCard(
      id: '${row['id']}',
      tenantId: tenantId,
      nombre: nombre,
      locale: '${row['locale'] ?? 'cs'}',
      status: '${row['status'] ?? 'activo'}',
      deleted: row['deleted_at'] != null,
      email: _trimOrNull(row['email']),
      tel: _trimOrNull(row['tel']),
      iban: _trimOrNull(row['iban']),
      notas: _trimOrNull(row['notas']),
      nie: nie,
      contacts: contacts,
      documents: documents,
      hiddenDocuments: hidden,
      coOwnerFolderId: coOwner?.folderId,
      coOwnerFolderNombre: coOwner?.folderNombre,
      coOwnerDireccion: coOwner?.direccion,
      coOwnerExpedienteId: coOwner?.expedienteId,
      holds: holds,
      erasureRequested: row['erasure_requested_at'] != null,
      poder: poder,
    );
  }

  Future<({bool nieConflict, String typedNie, String keepNie})> save({
    required String nombre,
    required String locale,
    required String nie,
    String? email,
    String? tel,
    String? iban,
    String? notas,
  }) async {
    const ok = (nieConflict: false, typedNie: '', keepNie: '');
    final current = state.valueOrNull;
    if (current == null || current.deleted) return ok;
    final client = trySupabaseClient();
    if (client == null) throw StateError('not configured');
    final trimmed = nombre.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('nombre');
    }
    await client
        .from('clientes')
        .update({
          'nombre': trimmed,
          'apellidos': null,
          'locale': locale,
          'email': _nullIfEmpty(email),
          'tel': _nullIfEmpty(tel),
          'iban': _nullIfEmpty(iban),
          'notas': _nullIfEmpty(notas),
        })
        .eq('id', current.id)
        .eq('tenant_id', current.tenantId);
    final nieSave = await persistClienteNie(
      client: client,
      tenantId: current.tenantId,
      clienteId: current.id,
      nieRaw: nie,
    );
    if (nieSave.conflict) {
      return (
        nieConflict: true,
        typedNie: nieSave.typedNie,
        keepNie: nieSave.keepNie,
      );
    }
    ref.invalidate(carpetaControllerProvider);
    _refresh(list: true);
    return ok;
  }

  Future<void> setStatus(String status) async {
    final current = state.valueOrNull;
    if (current == null || current.deleted) return;
    final client = trySupabaseClient();
    if (client == null) throw StateError('not configured');
    await client
        .from('clientes')
        .update({'status': status})
        .eq('id', current.id)
        .eq('tenant_id', current.tenantId);
    _refresh(list: true);
  }

  Future<void> softDelete() async {
    final current = state.valueOrNull;
    if (current == null || current.deleted) return;
    final client = trySupabaseClient();
    if (client == null) throw StateError('not configured');
    await client
        .from('clientes')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', current.id)
        .eq('tenant_id', current.tenantId);
    _refresh(list: true);
  }

  Future<void> restore() async {
    final current = state.valueOrNull;
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (current == null || auth == null || !canRestoreDeleted(auth)) return;
    final client = trySupabaseClient();
    if (client == null) throw StateError('not configured');
    await client
        .from('clientes')
        .update({'deleted_at': null})
        .eq('id', current.id)
        .eq('tenant_id', current.tenantId);
    _refresh(list: true);
  }

  Future<void> addContact({
    required String nombre,
    required String locale,
    String? relacion,
    String? tel,
    String? email,
  }) async {
    final current = state.valueOrNull;
    if (current == null || current.deleted) return;
    final trimmed = nombre.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('nombre');
    }
    final client = trySupabaseClient();
    if (client == null) throw StateError('not configured');
    await client.from('client_contacts').insert({
      'tenant_id': current.tenantId,
      'cliente_id': current.id,
      'nombre': trimmed,
      'locale': locale,
      'relacion': _nullIfEmpty(relacion),
      'tel': _nullIfEmpty(tel),
      'email': _nullIfEmpty(email),
    });
    _refresh();
  }

  Future<void> removeContact(String contactId) async {
    final current = state.valueOrNull;
    if (current == null || current.deleted) return;
    final client = trySupabaseClient();
    if (client == null) throw StateError('not configured');
    await client
        .from('client_contacts')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', contactId)
        .eq('tenant_id', current.tenantId);
    _refresh();
  }

  Future<void> attachDocument({
    required String tipo,
    required Uint8List bytes,
    required String originalName,
  }) async {
    final current = state.valueOrNull;
    if (current == null || current.deleted) return;
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (trySupabaseClient() == null) throw StateError('not configured');
    final path = documentoStoragePath(
      tenantId: current.tenantId,
      clienteId: current.id,
      originalName: originalName,
    );
    await uploadDocumentoBytes(
      path: path,
      bytes: bytes,
      originalName: originalName,
    );
    await insertDocumentoRow(
      tenantId: current.tenantId,
      clienteId: current.id,
      tipo: tipo,
      storagePath: path,
      originalName: originalName,
      createdBy: auth?.profile?.id,
    );
    startExtractInBackground(
      tenantId: current.tenantId,
      clienteId: current.id,
      storagePath: path,
      mime: mimeForOfficeFile(originalName),
      docTipo: tipo,
      bloqueKey: tipo,
      onDone: (_) => _refresh(),
    );
    _refresh();
  }

  /// Gestor ukládá návrh z dokladu na kartě. AI sem nesmí.
  Future<void> saveDocumentExtracted({
    required String documentId,
    required Map<String, String> fields,
  }) async {
    final current = state.valueOrNull;
    if (current == null || current.deleted || fields.isEmpty) return;
    final client = trySupabaseClient();
    if (client == null) throw StateError('not configured');
    ClienteDocumento? doc;
    for (final d in current.documents) {
      if (d.id == documentId) {
        doc = d;
        break;
      }
    }
    final prepared = prepareDocumentoExtract(
      fields: fields,
      existingBody: doc?.bodyText ?? '',
      currentTipo: doc?.tipo,
      cardName: current.nombre,
      cardNie: current.nie,
    );
    if (prepared.isEmpty) return;
    await client.from('documentos').update({
      'extracted': prepared.fields,
      if (prepared.bodyText != null) 'body_text': prepared.bodyText,
      if (prepared.nextTipo != null && prepared.nextTipo != doc?.tipo)
        'tipo': prepared.nextTipo,
    }).eq('id', documentId).eq('tenant_id', current.tenantId);
    await guardarFacturaRecibida(
      documentoId: documentId,
      fields: prepared.fields,
      docTipo: prepared.nextTipo ?? doc?.tipo,
    );
    ref.invalidate(facturasClienteProvider(current.id));
    _refresh();
  }

  Future<void> extractDocument(ClienteDocumento doc) async {
    final current = state.valueOrNull;
    if (current == null || current.deleted) return;
    startExtractInBackground(
      tenantId: current.tenantId,
      clienteId: current.id,
      storagePath: doc.storagePath,
      mime: mimeForOfficeFile(doc.originalName),
      docTipo: doc.tipo,
      bloqueKey: doc.tipo,
      onDone: (_) =>
          ref.invalidate(liveAiDraftsProvider(current.id)),
    );
  }

  Future<void> removeDocument(String documentId) async {
    final current = state.valueOrNull;
    if (current == null || current.deleted) return;
    final client = trySupabaseClient();
    if (client == null) throw StateError('not configured');
    await client
        .from('documentos')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', documentId)
        .eq('tenant_id', current.tenantId);
    _refresh();
  }

  Future<void> restoreDocument(String documentId) async {
    final current = state.valueOrNull;
    if (current == null || current.deleted) return;
    final client = trySupabaseClient();
    if (client == null) throw StateError('not configured');
    await client
        .from('documentos')
        .update({'deleted_at': null})
        .eq('id', documentId)
        .eq('tenant_id', current.tenantId);
    ref.invalidate(carpetaControllerProvider);
    _refresh();
  }

  /// Owner maže blob schovaného dokumentu. Řádek zůstane.
  Future<void> purgeDocumentStorage(String documentId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final client = trySupabaseClient();
    if (client == null) throw StateError('not configured');
    await client.rpc(
      'purge_documento_storage',
      params: {'p_documento_id': documentId},
    );
    _refresh();
  }

  Future<void> addLegalHold({
    required DateTime until,
    required String reason,
    String? documentoId,
  }) async {
    final current = state.valueOrNull;
    if (current == null || current.deleted) return;
    final client = trySupabaseClient();
    if (client == null) throw StateError('not configured');
    final why = reason.trim();
    if (why.isEmpty) throw ArgumentError('reason');
    await client.from('legal_holds').insert({
      'tenant_id': current.tenantId,
      'cliente_id': current.id,
      'documento_id': documentoId,
      'until': legalHoldUntilIso(until),
      'reason': why,
    });
    _refresh();
  }

  Future<void> releaseLegalHold(String holdId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final client = trySupabaseClient();
    if (client == null) throw StateError('not configured');
    await client.from('legal_holds').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', holdId).eq('tenant_id', current.tenantId);
    _refresh();
  }

  Future<void> anonymizeCliente() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final client = trySupabaseClient();
    if (client == null) throw StateError('not configured');
    await client.rpc(
      'anonymize_cliente',
      params: {'p_cliente_id': current.id},
    );
    ref.invalidate(carpetaControllerProvider);
    _refresh(list: true);
  }

  Future<String?> signedUrl(String storagePath) async {
    final client = trySupabaseClient();
    if (client == null) return null;
    return client.storage.from('documentos').createSignedUrl(storagePath, 120);
  }

  void _refresh({bool list = false}) {
    if (list) ref.invalidate(clientesListProvider);
    ref.invalidate(clienteAuditProvider(arg));
    ref.invalidateSelf();
  }
}

Future<List<ClienteHold>> _loadHolds({
  required dynamic client,
  required String tenantId,
  required String clienteId,
  required List<String> documentoIds,
}) async {
  try {
    final base = client
        .from('legal_holds')
        .select('id, until, reason, documento_id, cliente_id')
        .eq('tenant_id', tenantId)
        .isFilter('deleted_at', null);
    final rows = documentoIds.isEmpty
        ? await base.eq('cliente_id', clienteId)
        : await base.or(
            'cliente_id.eq.$clienteId,documento_id.in.(${documentoIds.join(',')})',
          );
    if (rows is! List) return const [];
    final ids = {for (final id in documentoIds) id};
    final out = <ClienteHold>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final cid = '${raw['cliente_id'] ?? ''}'.trim();
      final did = '${raw['documento_id'] ?? ''}'.trim();
      final forCard = cid == clienteId;
      final forDoc = did.isNotEmpty && ids.contains(did);
      if (!forCard && !forDoc) continue;
      final until = parseLegalHoldUntil(raw['until']);
      if (until == null) continue;
      out.add(
        ClienteHold(
          id: '${raw['id']}',
          until: until,
          reason: _trimOrNull(raw['reason']),
          documentoId: did.isEmpty || did == 'null' ? null : did,
        ),
      );
    }
    return out;
  } on Object {
    return const [];
  }
}

final clienteCardProvider =
    AsyncNotifierProvider.family<ClienteCardController, ClienteCard, String>(
      ClienteCardController.new,
    );

String? _trimOrNull(Object? value) {
  final s = '$value'.trim();
  if (s.isEmpty || s == 'null') return null;
  return s;
}

class _CoOwnerFolder {
  const _CoOwnerFolder({
    required this.folderId,
    required this.folderNombre,
    required this.direccion,
    this.expedienteId,
  });

  final String folderId;
  final String folderNombre;
  final String direccion;
  final String? expedienteId;
}

Future<_CoOwnerFolder?> _coOwnerFolderFor({
  required dynamic client,
  required String tenantId,
  required String clienteId,
}) async {
  try {
    final owned = await client
        .from('inmuebles')
        .select('id')
        .eq('cliente_id', clienteId)
        .eq('tenant_id', tenantId)
        .isFilter('deleted_at', null)
        .limit(1);
    if (owned is List && owned.isNotEmpty) return null;
    final tit = await client
        .from('inmueble_titulares')
        .select('inmueble_id')
        .eq('cliente_id', clienteId)
        .eq('lado', 'comprador')
        .isFilter('deleted_at', null)
        .limit(1)
        .maybeSingle();
    final inmId = '${tit?['inmueble_id'] ?? ''}'.trim();
    if (inmId.isEmpty) return null;
    final inm = await client
        .from('inmuebles')
        .select('id, direccion, cliente_id')
        .eq('id', inmId)
        .isFilter('deleted_at', null)
        .maybeSingle();
    if (inm == null) return null;
    final folderId = '${inm['cliente_id'] ?? ''}'.trim();
    if (folderId.isEmpty || folderId == clienteId) return null;
    final owner = await client
        .from('clientes')
        .select('nombre, apellidos')
        .eq('id', folderId)
        .maybeSingle();
    final folderNombre = [
      '${owner?['nombre'] ?? ''}'.trim(),
      '${owner?['apellidos'] ?? ''}'.trim(),
    ].where((s) => s.isNotEmpty).join(' ');
    final exp = await client
        .from('expedientes')
        .select('id')
        .eq('inmueble_id', inmId)
        .eq('tipo', 'compraventa')
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final expId = '${exp?['id'] ?? ''}'.trim();
    return _CoOwnerFolder(
      folderId: folderId,
      folderNombre: folderNombre,
      direccion: '${inm['direccion'] ?? ''}'.trim(),
      expedienteId: expId.isEmpty ? null : expId,
    );
  } on Object {
    return null;
  }
}

ClienteDocumento _clienteDocumentoFromRow(Map raw) {
  final t = transcriptFromDocumentoRow(raw);
  final bloque = '${raw['bloque_id'] ?? ''}'.trim();
  return ClienteDocumento(
    id: '${raw['id']}',
    tipo: '${raw['tipo'] ?? 'other'}',
    storagePath: '${raw['storage_path'] ?? ''}',
    originalName: '${raw['original_name'] ?? ''}'.trim(),
    extracted: t.fields,
    bodyText: t.bodyText,
    storagePurged: storagePurgedFromRow(raw),
    bloqueId: bloque.isEmpty || bloque == 'null' ? null : bloque,
  );
}

String? _nullIfEmpty(String? value) {
  final s = value?.trim() ?? '';
  return s.isEmpty ? null : s;
}
