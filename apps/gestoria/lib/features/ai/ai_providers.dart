import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import 'extract_text.dart';

class AiHit {
  const AiHit({
    required this.clienteId,
    required this.score,
    this.matchedVia,
    this.nombre = '',
  });

  final String clienteId;
  final int score;
  final String? matchedVia;
  final String nombre;
}

class AiPrefillDraft {
  const AiPrefillDraft({
    required this.clienteId,
    required this.bloqueKey,
    required this.fields,
    this.draftId,
    this.storagePath,
  });

  final String clienteId;
  final String bloqueKey;
  final Map<String, String> fields;
  final String? draftId;
  final String? storagePath;
}

/// Paměť aktuálního návrhu. Zdroj pravdy TTL je `ai_drafts`.
final aiPrefillProvider = StateProvider<AiPrefillDraft?>((ref) => null);

/// Živé návrhy z DB (24 h). AI sem zapisuje, desku ne.
final liveAiDraftsProvider =
    FutureProvider.family<List<AiPrefillDraft>, String>((ref, clienteId) async {
      ref.watch(authControllerProvider);
      final client = trySupabaseClient();
      final tenantId = ref
          .read(authControllerProvider)
          .valueOrNull
          ?.currentTenantId;
      if (client == null || tenantId == null) return const [];
      final rows = await client
          .from('ai_drafts')
          .select('id, bloque_key, fields, storage_path, expires_at')
          .eq('tenant_id', tenantId)
          .eq('cliente_id', clienteId)
          .isFilter('deleted_at', null)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false);
      final out = <AiPrefillDraft>[];
      if (rows is! List) return out;
      for (final raw in rows) {
        if (raw is! Map) continue;
        final fields = stringFieldMap(raw['fields']);
        if (fields.isEmpty) continue;
        out.add(
          AiPrefillDraft(
            draftId: '${raw['id']}',
            clienteId: clienteId,
            bloqueKey: '${raw['bloque_key'] ?? 'cliente_snapshot'}',
            fields: fields,
            storagePath: raw['storage_path']?.toString(),
          ),
        );
      }
      return out;
    });

Future<String?> persistAiDraft({
  required String tenantId,
  required String clienteId,
  required Map<String, String> fields,
  String bloqueKey = 'cliente_snapshot',
  String purpose = 'extract_text',
}) async {
  final client = trySupabaseClient();
  if (client == null || fields.isEmpty) return null;
  final uid = (await client.auth.getUser()).user?.id;
  try {
    final row = await client
        .from('ai_drafts')
        .insert({
          'tenant_id': tenantId,
          'cliente_id': clienteId,
          'created_by': uid,
          'purpose': purpose,
          'target': 'bloque',
          'bloque_key': bloqueKey,
          'fields': fields,
        })
        .select('id')
        .single();
    return '${row['id']}';
  } on Object {
    return null;
  }
}

Future<void> discardAiDraft(String? draftId) async {
  if (draftId == null || draftId.isEmpty) return;
  final client = trySupabaseClient();
  if (client == null) return;
  await client
      .from('ai_drafts')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', draftId);
}

Future<AiPrefillDraft?> extractDocumentDraft({
  required String tenantId,
  required String clienteId,
  required String storagePath,
  required String mime,
  String? docTipo,
  String bloqueKey = 'cliente_snapshot',
}) async {
  final client = trySupabaseClient();
  if (client == null) return null;
  final response = await client.functions.invoke(
    'extract-document',
    body: {
      'tenant_id': tenantId,
      'cliente_id': clienteId,
      'storage_path': storagePath,
      'mime': mime,
      if (docTipo != null && docTipo.isNotEmpty) 'doc_tipo': docTipo,
      'bloque_key': bloqueKey,
    },
  );
  final data = response.data;
  if (data is! Map || data['ok'] != true) return null;
  final fields = stringFieldMap(data['fields']);
  if (fields.isEmpty) return null;
  return AiPrefillDraft(
    draftId: data['draft_id']?.toString(),
    clienteId: clienteId,
    bloqueKey: '${data['bloque_key'] ?? bloqueKey}',
    fields: fields,
    storagePath: storagePath,
  );
}

Future<List<AiHit>> aiSearchClients(String q) async {
  final client = trySupabaseClient();
  if (client == null || q.trim().isEmpty) return [];
  final hits = await client.rpc(
    'search_clients',
    params: {'p_q': q.trim(), 'p_limit': 10},
  );
  final ids = <String>[];
  final score = <String, AiHit>{};
  if (hits is List) {
    for (final raw in hits) {
      if (raw is! Map) continue;
      final id = '${raw['cliente_id']}';
      ids.add(id);
      score[id] = AiHit(
        clienteId: id,
        score: raw['score'] is int
            ? raw['score'] as int
            : int.tryParse('${raw['score']}') ?? 0,
        matchedVia: raw['matched_via']?.toString(),
      );
    }
  }
  if (ids.isEmpty) return [];
  final rows = await client
      .from('clientes')
      .select('id, nombre, apellidos')
      .inFilter('id', ids);
  final named = <AiHit>[];
  for (final raw in rows as List) {
    if (raw is! Map) continue;
    final id = '${raw['id']}';
    final base = score[id];
    if (base == null) continue;
    final nombre = [
      '${raw['nombre'] ?? ''}'.trim(),
      '${raw['apellidos'] ?? ''}'.trim(),
    ].where((s) => s.isNotEmpty).join(' ');
    named.add(
      AiHit(
        clienteId: id,
        score: base.score,
        matchedVia: base.matchedVia,
        nombre: nombre,
      ),
    );
  }
  named.sort((a, b) => b.score.compareTo(a.score));
  return named;
}

class AiDraftMessage {
  const AiDraftMessage({
    required this.mensajeId,
    required this.templateKey,
    required this.bloqueKey,
  });

  final String mensajeId;
  final String templateKey;
  final String bloqueKey;
}

/// Copilot nachystá draft. Odeslání v UI, ne tady.
Future<AiDraftMessage> draftMessageFromHoles({
  required String tenantId,
  required String clienteId,
}) async {
  final client = trySupabaseClient();
  if (client == null) throw StateError('not configured');
  try {
    final response = await client.functions.invoke(
      'ai-draft-message',
      body: {'tenant_id': tenantId, 'cliente_id': clienteId},
    );
    final data = response.data;
    if (data is! Map || data['ok'] != true) {
      final err = data is Map ? '${data['error'] ?? ''}' : '';
      if (err == 'no_holes') throw StateError('no_holes');
      throw StateError(err.isEmpty ? 'draft failed' : err);
    }
    return AiDraftMessage(
      mensajeId: '${data['mensaje_id']}',
      templateKey: '${data['template_key'] ?? 'recordatorio'}',
      bloqueKey: '${data['bloque_key'] ?? ''}',
    );
  } on StateError {
    rethrow;
  } on Object catch (e) {
    if ('$e'.contains('no_holes')) throw StateError('no_holes');
    throw StateError('draft failed');
  }
}

class AiDocFact {
  const AiDocFact({
    required this.tipo,
    this.nombre,
    this.expiry,
    this.amount,
    this.consumption,
    this.docNumber,
  });

  final String tipo;
  final String? nombre;
  final String? expiry;
  final String? amount;
  final String? consumption;
  final String? docNumber;
}

class AiFactAnswer {
  const AiFactAnswer({
    required this.clienteId,
    required this.nombre,
    this.tel,
    this.email,
    this.docs = const [],
  });

  final String clienteId;
  final String nombre;
  final String? tel;
  final String? email;
  final List<AiDocFact> docs;

  bool get hasAnything =>
      (tel != null && tel!.isNotEmpty) ||
      (email != null && email!.isNotEmpty) ||
      docs.isNotEmpty;
}

/// MIME z přípony. Edge Function podle toho volí vision vs. PDF.
String mimeForOfficeFile(String name, {String? extension}) {
  final e = (extension ?? name.split('.').last).toLowerCase();
  return switch (e) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'pdf' => 'application/pdf',
    _ => 'image/jpeg',
  };
}

/// Search + uložené doklady. Nic se nezapisuje.
Future<AiFactAnswer?> askClienteFacts(String q) async {
  final hits = await aiSearchClients(q);
  if (hits.isEmpty) return null;
  return askClienteFactsForId(hits.first.clienteId, nombre: hits.first.nombre);
}

/// Otevřená karta má přednost před hledáním z věty.
Future<AiFactAnswer?> askClienteFactsForId(
  String clienteId, {
  String nombre = '',
}) async {
  final client = trySupabaseClient();
  if (client == null) {
    return AiFactAnswer(clienteId: clienteId, nombre: nombre);
  }
  try {
    final snap = await client.rpc(
      'ai_get_cliente',
      params: {'p_cliente_id': clienteId},
    );
    final docs = <AiDocFact>[];
    if (snap is Map && snap['documentos'] is List) {
      for (final raw in snap['documentos'] as List) {
        if (raw is! Map) continue;
        final extracted = stringFieldMap(raw['extracted']);
        docs.add(
          AiDocFact(
            tipo: '${raw['tipo']}',
            nombre:
                extracted['fields.nombre'] ?? raw['original_name']?.toString(),
            expiry: extracted['fields.expiry'],
            amount: extracted['fields.amount'],
            consumption: extracted['fields.consumption'],
            docNumber: extracted['fields.docNumber'],
          ),
        );
      }
    }
    final cliente = snap is Map ? snap['cliente'] : null;
    var resolvedNombre = nombre;
    String? tel;
    String? email;
    if (cliente is Map) {
      final n = '${cliente['nombre'] ?? ''}'.trim();
      if (n.isNotEmpty) resolvedNombre = n;
      final t = '${cliente['tel'] ?? ''}'.trim();
      if (t.isNotEmpty) tel = t;
      final e = '${cliente['email'] ?? ''}'.trim();
      if (e.isNotEmpty) email = e;
    }
    final drafts = await client
        .from('ai_drafts')
        .select('fields, bloque_key, expires_at')
        .eq('cliente_id', clienteId)
        .isFilter('deleted_at', null)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String());
    if (drafts is List) {
      for (final raw in drafts) {
        if (raw is! Map) continue;
        final fields = stringFieldMap(raw['fields']);
        if (fields.isEmpty) continue;
        final tipo = '${raw['bloque_key'] ?? ''}';
        docs.add(
          AiDocFact(
            tipo: tipo.isEmpty ? 'other' : tipo,
            nombre: fields['fields.nombre'],
            expiry: fields['fields.expiry'],
            amount: fields['fields.amount'],
            consumption: fields['fields.consumption'],
            docNumber: fields['fields.docNumber'],
          ),
        );
      }
    }
    return AiFactAnswer(
      clienteId: clienteId,
      nombre: resolvedNombre,
      tel: tel,
      email: email,
      docs: docs,
    );
  } on Object {
    return AiFactAnswer(clienteId: clienteId, nombre: nombre);
  }
}
