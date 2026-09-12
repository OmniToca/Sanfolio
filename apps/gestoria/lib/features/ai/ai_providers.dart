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
  });

  final String clienteId;
  final String bloqueKey;
  final Map<String, String> fields;
  final String? draftId;
}

/// Paměť aktuálního návrhu. Zdroj pravdy TTL je `ai_drafts`.
final aiPrefillProvider = StateProvider<AiPrefillDraft?>((ref) => null);

/// Živý návrh z DB (24 h). AI sem zapisuje, desku ne.
final liveAiDraftProvider =
    FutureProvider.family<AiPrefillDraft?, String>((ref, clienteId) async {
  ref.watch(authControllerProvider);
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return null;
  final row = await client
      .from('ai_drafts')
      .select('id, bloque_key, fields, expires_at')
      .eq('tenant_id', tenantId)
      .eq('cliente_id', clienteId)
      .isFilter('deleted_at', null)
      .gt('expires_at', DateTime.now().toUtc().toIso8601String())
      .order('created_at', ascending: false)
      .limit(1)
      .maybeSingle();
  if (row == null) return null;
  final fields = stringFieldMap(row['fields']);
  if (fields.isEmpty) return null;
  return AiPrefillDraft(
    draftId: '${row['id']}',
    clienteId: clienteId,
    bloqueKey: '${row['bloque_key'] ?? 'cliente_snapshot'}',
    fields: fields,
  );
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
  await client.from('ai_drafts').update({
    'deleted_at': DateTime.now().toUtc().toIso8601String(),
  }).eq('id', draftId);
}

Future<AiPrefillDraft?> extractDocumentDraft({
  required String tenantId,
  required String clienteId,
  required String storagePath,
  required String mime,
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
    },
  );
  final data = response.data;
  if (data is! Map || data['ok'] != true) return null;
  final fields = stringFieldMap(data['fields']);
  if (fields.isEmpty) return null;
  return AiPrefillDraft(
    draftId: data['draft_id']?.toString(),
    clienteId: clienteId,
    bloqueKey: '${data['bloque_key'] ?? 'cliente_snapshot'}',
    fields: fields,
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
      body: {
        'tenant_id': tenantId,
        'cliente_id': clienteId,
      },
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
