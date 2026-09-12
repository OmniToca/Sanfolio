import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

/// Zápis z panelu. AI sem píše zprávy; kartu klienta ne.
class AiChatMessage {
  const AiChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String role;
  final String content;
  final DateTime createdAt;

  bool get fromUser => role == 'user';
}

/// Odkaz ze zprávy na kartu / desku. Navigaci spouští gestor, ne model.
class AiChatOpen {
  const AiChatOpen({
    required this.clienteId,
    required this.label,
    this.carpeta = false,
  });

  final String clienteId;
  final String label;
  final bool carpeta;

  String get route =>
      carpeta ? '/clientes/$clienteId/carpeta' : '/clientes/$clienteId';
}

/// Text k zobrazení + volitelné otevření / prefill. Ukládá se do `content`.
class AiChatPayload {
  const AiChatPayload({
    required this.text,
    this.opens = const [],
    this.fields = const {},
  });

  final String text;
  final List<AiChatOpen> opens;
  final Map<String, String> fields;
}

class AiChatState {
  const AiChatState({
    this.conversationId,
    this.messages = const [],
    this.busy = false,
  });

  final String? conversationId;
  final List<AiChatMessage> messages;
  final bool busy;

  AiChatState copyWith({
    String? conversationId,
    List<AiChatMessage>? messages,
    bool? busy,
  }) {
    return AiChatState(
      conversationId: conversationId ?? this.conversationId,
      messages: messages ?? this.messages,
      busy: busy ?? this.busy,
    );
  }
}

/// Na širokém stole otevřený; null = výchozí podle šířky.
final aiPanelOpenProvider = StateProvider<bool?>((ref) => null);

bool aiPanelVisible({required double width, required bool? preference}) {
  if (preference != null) return preference;
  return width >= 1100;
}

/// Dock vedle desky; na úzkém okně překryv, ať se netlačí obsah.
bool aiPanelDocked(double width) => width >= 1100;

String? clienteIdFromOfficePath(String path) {
  final parts = path.split('/');
  final i = parts.indexOf('clientes');
  if (i < 0 || i + 1 >= parts.length) return null;
  final id = parts[i + 1];
  if (id.isEmpty || id == 'carpeta' || id == 'mensaje') return null;
  return id;
}

String encodeAiChatPayload(AiChatPayload payload) {
  if (payload.opens.isEmpty && payload.fields.isEmpty) return payload.text;
  return jsonEncode({
    'v': 1,
    'text': payload.text,
    'opens': [
      for (final open in payload.opens)
        {
          'cliente_id': open.clienteId,
          'label': open.label,
          'carpeta': open.carpeta,
        },
    ],
    if (payload.fields.isNotEmpty) 'fields': payload.fields,
  });
}

AiChatPayload decodeAiChatPayload(String content) {
  final trimmed = content.trim();
  if (!trimmed.startsWith('{')) return AiChatPayload(text: content);
  try {
    final raw = jsonDecode(trimmed);
    if (raw is! Map) return AiChatPayload(text: content);
    if (raw['v'] != 1 && raw['text'] == null) {
      return AiChatPayload(text: content);
    }
    final opens = <AiChatOpen>[];
    final listed = raw['opens'];
    if (listed is List) {
      for (final item in listed) {
        if (item is! Map) continue;
        final id = '${item['cliente_id'] ?? ''}'.trim();
        if (id.isEmpty) continue;
        opens.add(
          AiChatOpen(
            clienteId: id,
            label: '${item['label'] ?? ''}',
            carpeta: item['carpeta'] == true,
          ),
        );
      }
    }
    final fields = <String, String>{};
    final rawFields = raw['fields'];
    if (rawFields is Map) {
      for (final entry in rawFields.entries) {
        final value = '${entry.value}'.trim();
        if (value.isEmpty) continue;
        fields['${entry.key}'] = value;
      }
    }
    return AiChatPayload(
      text: '${raw['text'] ?? content}',
      opens: opens,
      fields: fields,
    );
  } on Object {
    return AiChatPayload(text: content);
  }
}

class AiChatController extends AsyncNotifier<AiChatState> {
  @override
  Future<AiChatState> build() async {
    ref.watch(authControllerProvider);
    return _load();
  }

  Future<AiChatState> _load() async {
    final client = trySupabaseClient();
    final auth = ref.read(authControllerProvider).valueOrNull;
    final tenantId = auth?.currentTenantId;
    final uid = auth?.profile?.id;
    if (client == null || tenantId == null || uid == null) {
      return const AiChatState();
    }
    final conv = await client
        .from('ai_conversations')
        .select('id')
        .eq('tenant_id', tenantId)
        .eq('created_by', uid)
        .isFilter('deleted_at', null)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (conv == null) return const AiChatState();
    final id = '${conv['id']}';
    final rows = await client
        .from('ai_messages')
        .select('id, role, content, created_at')
        .eq('conversation_id', id)
        .isFilter('deleted_at', null)
        .order('created_at');
    return AiChatState(conversationId: id, messages: parseAiChatMessages(rows));
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = AsyncData(await _load());
  }

  Future<void> newThread() async {
    final current = state.valueOrNull;
    final id = current?.conversationId;
    final client = trySupabaseClient();
    if (client != null && id != null) {
      await client
          .from('ai_conversations')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', id);
    }
    state = const AsyncData(AiChatState());
  }

  Future<void> addUser(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _append(role: 'user', content: trimmed);
  }

  Future<void> addAssistant(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _append(role: 'assistant', content: trimmed);
  }

  Future<void> _append({required String role, required String content}) async {
    final client = trySupabaseClient();
    final auth = ref.read(authControllerProvider).valueOrNull;
    final tenantId = auth?.currentTenantId;
    final uid = auth?.profile?.id;
    if (client == null || tenantId == null || uid == null) {
      throw StateError('not configured');
    }

    final local = AiChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}-$role',
      role: role,
      content: content,
      createdAt: DateTime.now().toUtc(),
    );
    var snap = state.valueOrNull ?? const AiChatState();
    final optimistic = [...snap.messages, local];
    state = AsyncData(
      AiChatState(
        conversationId: snap.conversationId,
        messages: optimistic,
        busy: true,
      ),
    );
    try {
      var convId = snap.conversationId;
      if (convId == null) {
        final locale = auth?.profile?.locale ?? 'cs';
        final row = await client
            .from('ai_conversations')
            .insert({
              'tenant_id': tenantId,
              'created_by': uid,
              'locale': locale,
            })
            .select('id')
            .single();
        convId = '${row['id']}';
      }
      final row = await client
          .from('ai_messages')
          .insert({
            'tenant_id': tenantId,
            'conversation_id': convId,
            'role': role,
            'content': content,
          })
          .select('id, role, content, created_at')
          .single();
      await client
          .from('ai_conversations')
          .update({'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', convId);
      final msg = parseAiChatMessage(row) ?? local;
      final next = [...snap.messages, msg];
      state = AsyncData(AiChatState(conversationId: convId, messages: next));
    } on Object {
      // Odpověď v panelu musí zůstat i když zápis do DB spadne.
      state = AsyncData(
        AiChatState(conversationId: snap.conversationId, messages: optimistic),
      );
    }
  }
}

final aiChatProvider = AsyncNotifierProvider<AiChatController, AiChatState>(
  AiChatController.new,
);

List<AiChatMessage> parseAiChatMessages(Object? rows) {
  if (rows is! List) return const [];
  final out = <AiChatMessage>[];
  for (final raw in rows) {
    final message = parseAiChatMessage(raw);
    if (message != null) out.add(message);
  }
  return out;
}

AiChatMessage? parseAiChatMessage(Object? raw) {
  if (raw is! Map) return null;
  final created = DateTime.tryParse('${raw['created_at'] ?? ''}');
  if (created == null) return null;
  final role = '${raw['role'] ?? ''}';
  if (role != 'user' && role != 'assistant' && role != 'tool') return null;
  return AiChatMessage(
    id: '${raw['id']}',
    role: role,
    content: '${raw['content'] ?? ''}',
    createdAt: created.toUtc(),
  );
}
