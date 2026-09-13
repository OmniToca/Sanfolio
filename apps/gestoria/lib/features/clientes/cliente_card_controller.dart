import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/documents/documento_storage.dart';
import '../ai/ai_providers.dart';
import '../ai/extract_text.dart';
import 'cliente_audit.dart';
import 'clientes_providers.dart';

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
  });

  final String id;
  final String tipo;
  final String storagePath;
  final String originalName;
  final Map<String, String> extracted;
  final String? bodyText;
  final bool storagePurged;

  ClienteDocumento copyWith({
    Map<String, String>? extracted,
    String? bodyText,
    bool? storagePurged,
  }) {
    return ClienteDocumento(
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

/// Koš na kartě: jen schované s originálem. Vysypané zmizí z UI, řádek v DB zůstane.
List<ClienteDocumento> trashVisibleOnCard(List<ClienteDocumento> hidden) {
  return [
    for (final d in hidden.reversed)
      if (!d.storagePurged) d,
  ];
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
          'deleted_at, client_identifiers(kind, value_raw, deleted_at)',
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

    String? nie;
    final ids = row['client_identifiers'];
    if (ids is List) {
      for (final item in ids) {
        if (item is! Map || item['deleted_at'] != null) continue;
        final v = '${item['value_raw'] ?? ''}'.trim();
        if (v.isNotEmpty) {
          nie = v;
          break;
        }
      }
    }

    final docsRaw = await client
        .from('documentos')
        .select(
          'id, tipo, storage_path, original_name, extracted, body_text, '
          'storage_purged_at, deleted_at',
        )
        .eq('cliente_id', clienteId)
        .eq('tenant_id', tenantId)
        .isFilter('bloque_id', null)
        .order('created_at');

    final documents = <ClienteDocumento>[];
    final hidden = <ClienteDocumento>[];
    for (final raw in docsRaw as List) {
      if (raw is! Map) continue;
      final doc = _clienteDocumentoFromRow(raw);
      if (raw['deleted_at'] != null) {
        hidden.add(doc);
      } else {
        documents.add(doc);
      }
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
    );
  }

  Future<void> save({
    required String nombre,
    required String locale,
    String? email,
    String? tel,
    String? iban,
    String? notas,
  }) async {
    final current = state.valueOrNull;
    if (current == null || current.deleted) return;
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
    _refresh(list: true);
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
    final client = trySupabaseClient();
    final auth = ref.read(authControllerProvider).valueOrNull;
    if (client == null) throw StateError('not configured');
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
    try {
      await client.from('documentos').insert({
        'tenant_id': current.tenantId,
        'cliente_id': current.id,
        'tipo': tipo,
        'storage_path': path,
        'original_name': originalName,
        if (auth?.profile?.id != null) 'created_by': auth!.profile!.id,
      });
    } on Object {
      await rollbackDocumentoUpload(path);
      throw OfficeUploadException('db');
    }
    await extractDocumentDraft(
      tenantId: current.tenantId,
      clienteId: current.id,
      storagePath: path,
      mime: mimeForOfficeFile(originalName),
      docTipo: tipo,
      bloqueKey: tipo,
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
    final t = splitDocumentoTranscript(fields);
    if (t.fields.isEmpty && t.bodyText == null) return;
    await client.from('documentos').update({
      'extracted': t.fields,
      if (t.bodyText != null) 'body_text': t.bodyText,
    }).eq('id', documentId).eq('tenant_id', current.tenantId);
    _refresh();
  }

  Future<void> extractDocument(ClienteDocumento doc) async {
    final current = state.valueOrNull;
    if (current == null || current.deleted) return;
    await extractDocumentDraft(
      tenantId: current.tenantId,
      clienteId: current.id,
      storagePath: doc.storagePath,
      mime: mimeForOfficeFile(doc.originalName),
      docTipo: doc.tipo,
      bloqueKey: doc.tipo,
    );
    ref.invalidate(liveAiDraftsProvider(current.id));
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

final clienteCardProvider =
    AsyncNotifierProvider.family<ClienteCardController, ClienteCard, String>(
      ClienteCardController.new,
    );

String? _trimOrNull(Object? value) {
  final s = '$value'.trim();
  if (s.isEmpty || s == 'null') return null;
  return s;
}

ClienteDocumento _clienteDocumentoFromRow(Map raw) {
  final t = transcriptFromDocumentoRow(raw);
  return ClienteDocumento(
    id: '${raw['id']}',
    tipo: '${raw['tipo'] ?? 'other'}',
    storagePath: '${raw['storage_path'] ?? ''}',
    originalName: '${raw['original_name'] ?? ''}'.trim(),
    extracted: t.fields,
    bodyText: t.bodyText,
    storagePurged: storagePurgedFromRow(raw),
  );
}

String? _nullIfEmpty(String? value) {
  final s = value?.trim() ?? '';
  return s.isEmpty ? null : s;
}
