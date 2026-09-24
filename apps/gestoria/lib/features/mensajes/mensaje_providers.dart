import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MensajeCliente {
  const MensajeCliente({
    required this.id,
    required this.nombre,
    required this.locale,
    this.email,
    this.tel,
  });

  final String id;
  final String nombre;
  final String locale;
  final String? email;
  final String? tel;
}

final mensajeClienteProvider =
    FutureProvider.family<MensajeCliente?, String>((ref, clienteId) async {
  ref.watch(authControllerProvider);
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return null;
  final row = await client
      .from('clientes')
      .select('id, nombre, apellidos, email, tel, locale')
      .eq('id', clienteId)
      .eq('tenant_id', tenantId)
      .isFilter('deleted_at', null)
      .maybeSingle();
  if (row == null) return null;
  final nombre = [
    '${row['nombre'] ?? ''}'.trim(),
    '${row['apellidos'] ?? ''}'.trim(),
  ].where((s) => s.isNotEmpty).join(' ');
  final email = '${row['email'] ?? ''}'.trim();
  final tel = '${row['tel'] ?? ''}'.trim();
  return MensajeCliente(
    id: '${row['id']}',
    nombre: nombre,
    locale: '${row['locale'] ?? 'cs'}',
    email: email.isEmpty ? null : email,
    tel: tel.isEmpty ? null : tel,
  );
});

/// Outbound text: překlad do locale klienta, dokud není překladač = originál.
/// Originál vždy v `cuerpo` / `locale_original`.
Future<String> translateOutbound({
  required String text,
  required String targetLocale,
  required bool sendTranslated,
  required String tenantId,
}) async {
  if (!sendTranslated || text.trim().isEmpty || targetLocale == 'es') {
    return text;
  }
  final client = trySupabaseClient();
  if (client == null || tenantId.trim().isEmpty) return text;
  try {
    final response = await client.functions.invoke(
      'translate-message',
      body: {
        'tenant_id': tenantId,
        'text': text,
        'source_locale': 'es',
        'target_locale': targetLocale,
      },
    );
    final data = response.data;
    if (data is Map && data['ok'] == true && data['text'] is String) {
      final out = '${data['text']}'.trim();
      if (out.isNotEmpty) return out;
    }
  } on Object {
    // Bez klíče / výpadek: odejde originál, nic se netváří.
  }
  return text;
}
Future<void> recordMensaje({
  required String tenantId,
  required String clienteId,
  required String canal,
  required String asunto,
  required String cuerpoOriginal,
  required String localeOriginal,
  required String outboundLocale,
  required String outboundBody,
  required String status,
  String? templateKey,
  String? bloqueId,
}) async {
  final client = trySupabaseClient();
  final uid = client?.auth.currentUser?.id;
  if (client == null) {
    throw StateError('not configured');
  }
  await client.from('mensajes').insert({
    'tenant_id': tenantId,
    'cliente_id': clienteId,
    'canal': canal,
    'asunto': asunto,
    'cuerpo': cuerpoOriginal,
    'locale_original': localeOriginal,
    'translations': {outboundLocale: outboundBody},
    'status': status,
    'template_key': ?templateKey,
    'bloque_id': ?bloqueId,
    'sent_at': status == 'sent' ? DateTime.now().toUtc().toIso8601String() : null,
    'created_by': uid,
  });
}

class ClienteMensaje {
  const ClienteMensaje({
    required this.id,
    required this.status,
    required this.cuerpo,
    required this.localeOriginal,
    required this.translations,
    this.asunto,
    this.canal,
    this.sentAt,
    this.createdAt,
    this.messageIdHeader,
    this.bounceAt,
    this.bounceReason,
  });

  final String id;
  final String status;
  final String cuerpo;
  final String localeOriginal;
  final Map<String, String> translations;
  final String? asunto;
  final String? canal;
  final DateTime? sentAt;
  final DateTime? createdAt;
  final String? messageIdHeader;
  final DateTime? bounceAt;
  final String? bounceReason;

  /// Překlad vedle originálu. Stejný text neschováváme jako „druhý jazyk“.
  String? translationBesideOriginal(String clientLocale) {
    if (clientLocale.isEmpty || clientLocale == localeOriginal) {
      return null;
    }
    final t = translations[clientLocale]?.trim();
    if (t == null || t.isEmpty || t == cuerpo) return null;
    return t;
  }
}

bool mensajeInHistory(String status) =>
    status == 'draft' || status == 'sent';

final clienteMensajesProvider =
    FutureProvider.family<List<ClienteMensaje>, String>((ref, clienteId) async {
  ref.watch(authControllerProvider);
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return [];
  final rows = await client
      .from('mensajes')
      .select(
        'id, status, asunto, cuerpo, locale_original, translations, '
        'canal, sent_at, created_at, message_id_header, bounce_at, bounce_reason',
      )
      .eq('cliente_id', clienteId)
      .eq('tenant_id', tenantId)
      .isFilter('deleted_at', null)
      .inFilter('status', ['draft', 'sent'])
      .order('created_at', ascending: false);
  final out = <ClienteMensaje>[];
  for (final raw in rows as List) {
    if (raw is! Map) continue;
    final translations = <String, String>{};
    final tr = raw['translations'];
    if (tr is Map) {
      for (final e in tr.entries) {
        translations['${e.key}'] = '${e.value}';
      }
    }
    out.add(
      ClienteMensaje(
        id: '${raw['id']}',
        status: '${raw['status'] ?? ''}',
        cuerpo: '${raw['cuerpo'] ?? ''}',
        localeOriginal: '${raw['locale_original'] ?? 'es'}',
        translations: translations,
        asunto: _trimOrNull(raw['asunto']),
        canal: _trimOrNull(raw['canal']),
        sentAt: raw['sent_at'] == null
            ? null
            : DateTime.tryParse('${raw['sent_at']}'),
        createdAt: raw['created_at'] == null
            ? null
            : DateTime.tryParse('${raw['created_at']}'),
        messageIdHeader: _trimOrNull(raw['message_id_header']),
        bounceAt: raw['bounce_at'] == null
            ? null
            : DateTime.tryParse('${raw['bounce_at']}'),
        bounceReason: _trimOrNull(raw['bounce_reason']),
      ),
    );
  }
  return out;
});

String? _trimOrNull(Object? v) {
  final s = '$v'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

class SendClientMessageResult {
  const SendClientMessageResult({
    required this.ok,
    this.notConfigured = false,
    this.error,
  });

  final bool ok;
  final bool notConfigured;
  final String? error;
}

/// Resend z kanceláře. Bez klíče → [notConfigured], Flutter otevře Gmail.
/// AI tuhle funkci nevolá.
Future<SendClientMessageResult> sendClientMessage({
  required String tenantId,
  required String clienteId,
  required String asunto,
  required String cuerpoOriginal,
  required String outboundBody,
  required String outboundLocale,
  String? templateKey,
  String? postaMessageId,
}) async {
  final client = trySupabaseClient();
  if (client == null) {
    return const SendClientMessageResult(ok: false, notConfigured: true);
  }
  try {
    final response = await client.functions.invoke(
      'send-client-message',
      body: {
        'tenant_id': tenantId,
        'cliente_id': clienteId,
        'asunto': asunto,
        'cuerpo_original': cuerpoOriginal,
        'outbound_body': outboundBody,
        'outbound_locale': outboundLocale,
        if (templateKey != null && templateKey.isNotEmpty)
          'template_key': templateKey,
        if (postaMessageId != null && postaMessageId.isNotEmpty)
          'posta_message_id': postaMessageId,
      },
    );
    return _sendResultFrom(response.status, response.data);
  } on FunctionException catch (e) {
    return _sendResultFrom(e.status, e.details);
  } on Object {
    return const SendClientMessageResult(ok: false, error: 'send_failed');
  }
}

SendClientMessageResult _sendResultFrom(int? status, Object? data) {
  final map = data is Map ? Map<Object?, Object?>.from(data) : const {};
  final err = '${map['error'] ?? ''}'.trim();
  if (map['ok'] == true) {
    return const SendClientMessageResult(ok: true);
  }
  if (status == 503 || err == 'not_configured') {
    return const SendClientMessageResult(ok: false, notConfigured: true);
  }
  return SendClientMessageResult(
    ok: false,
    error: err.isEmpty ? 'send_failed' : err,
  );
}

/// Soft stav, ne DELETE. Audit trigger zapíše `mensajes.discarded`.
Future<void> discardMensaje({
  required String tenantId,
  required String mensajeId,
}) async {
  final client = trySupabaseClient();
  if (client == null) throw StateError('not configured');
  await client
      .from('mensajes')
      .update({'status': 'discarded'})
      .eq('id', mensajeId)
      .eq('tenant_id', tenantId)
      .eq('status', 'draft');
}
