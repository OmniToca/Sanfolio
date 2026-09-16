import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/documents/documento_storage.dart';
import '../../core/identity/nie_persist.dart';
import '../ai/ai_providers.dart';
import '../ai/documento_fields.dart';
import '../carpeta/bloque_template.dart';
import 'posta_address.dart';

class PostaAccount {
  const PostaAccount({
    required this.id,
    required this.ingestAddress,
    required this.ingestLocal,
    required this.ingestDomain,
  });

  final String id;
  final String ingestAddress;
  final String ingestLocal;
  final String ingestDomain;
}

class PostaAttachment {
  const PostaAttachment({
    required this.id,
    required this.filename,
    required this.storagePath,
    this.mime,
    this.byteSize,
    this.documentoId,
  });

  final String id;
  final String filename;
  final String storagePath;
  final String? mime;
  final int? byteSize;
  final String? documentoId;

  bool get filed => documentoId != null && documentoId!.isNotEmpty;
}

class PostaMessage {
  const PostaMessage({
    required this.id,
    required this.fromAddress,
    required this.receivedAt,
    required this.status,
    this.fromName,
    this.subject,
    this.bodyText,
    this.clienteId,
    this.clienteNombre,
    this.matchMethod,
    this.gmailUrl,
    this.messageIdHeader,
    this.mensajeId,
    this.attachments = const [],
  });

  final String id;
  final String fromAddress;
  final DateTime receivedAt;
  final String status;
  final String? fromName;
  final String? subject;
  final String? bodyText;
  final String? clienteId;
  final String? clienteNombre;
  final String? matchMethod;
  final String? gmailUrl;
  final String? messageIdHeader;
  final String? mensajeId;
  final List<PostaAttachment> attachments;

  bool get hasAttachments => attachments.isNotEmpty;
  bool get hasUnfiled => attachments.any((a) => !a.filed);
  int get unfiledCount => attachments.where((a) => !a.filed).length;
  bool get assigned => status == 'assigned' && (clienteId ?? '').isNotEmpty;

  String get fromLabel {
    final name = fromName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return fromAddress;
  }

  String? get openInGmail =>
      (gmailUrl != null && gmailUrl!.isNotEmpty)
          ? gmailUrl
          : gmailSearchUrl(messageIdHeader);
}

class PostaFileTarget {
  const PostaFileTarget({
    required this.labelKey,
    this.bloqueId,
    this.templateKey,
    this.requiredDocTypes = const [],
    this.place,
    this.suggested = false,
    this.expedienteId,
  });

  final String labelKey;
  final String? bloqueId;
  final String? templateKey;
  final List<String> requiredDocTypes;

  /// Adresa finca / titul spisu, když má klient víc desek stejného bloku.
  final String? place;
  final bool suggested;
  final String? expedienteId;

  bool get isCard => bloqueId == null || bloqueId!.isEmpty;
}

/// Jeden návrh bloku = lze nabídnout uložení bez dalšího výběru. Dvě finca ne.
PostaFileTarget? uniqueSuggestedFileTarget(Iterable<PostaFileTarget> targets) {
  final hits = [
    for (final t in targets)
      if (t.suggested && !t.isCard) t,
  ];
  if (hits.length != 1) return null;
  return hits.first;
}

class PostaClienteHit {
  const PostaClienteHit({
    required this.id,
    required this.nombre,
    this.email,
    this.nie,
    this.matchMethod,
    this.auto = false,
  });

  final String id;
  final String nombre;
  final String? email;
  final String? nie;
  final String? matchMethod;
  final bool auto;

  String get subtitle {
    return [
      if ((nie ?? '').isNotEmpty) nie!,
      if ((email ?? '').isNotEmpty) email!,
    ].join(' · ');
  }
}

final postaAccountProvider = FutureProvider<PostaAccount?>((ref) async {
  ref.watch(authControllerProvider);
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return null;
  final raw = await client.rpc(
    'ensure_posta_account',
    params: {'p_tenant_id': tenantId},
  );
  final row = _firstMap(raw);
  if (row == null) return null;
  return PostaAccount(
    id: '${row['id']}',
    ingestAddress: '${row['ingest_address'] ?? ''}',
    ingestLocal: '${row['ingest_local'] ?? ''}',
    ingestDomain: '${row['ingest_domain'] ?? ''}',
  );
});

final postaUnassignedCountProvider = FutureProvider<int>((ref) async {
  ref.watch(authControllerProvider);
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return 0;
  final raw = await client.rpc(
    'posta_unassigned_attachment_count',
    params: {'p_tenant_id': tenantId},
  );
  return int.tryParse('$raw') ?? 0;
});

final postaUnfiledCountProvider = FutureProvider<int>((ref) async {
  ref.watch(authControllerProvider);
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return 0;
  final raw = await client.rpc(
    'posta_unfiled_count',
    params: {'p_tenant_id': tenantId},
  );
  return int.tryParse('$raw') ?? 0;
});

final postaFilterProvider = StateProvider<String>((ref) => 'unassigned');

final postaListProvider = FutureProvider<List<PostaMessage>>((ref) async {
  ref.watch(authControllerProvider);
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return [];
  final filter = ref.watch(postaFilterProvider);
  var query = client
      .from('posta_messages')
      .select(
        'id, from_address, from_name, subject, received_at, status, '
        'cliente_id, match_method, gmail_url, message_id_header, mensaje_id, '
        'clientes(nombre, apellidos, razon_social), '
        'posta_attachments(id, filename, mime, byte_size, storage_path, documento_id, deleted_at)',
      )
      .eq('tenant_id', tenantId)
      .isFilter('deleted_at', null);
  query = switch (filter) {
    'unassigned' || 'assigned' => query.eq('status', filter),
    _ => query.neq('status', 'ignored'),
  };
  final rows = await query.order('received_at', ascending: false).limit(80);
  final out = <PostaMessage>[];
  for (final raw in rows as List) {
    if (raw is! Map) continue;
    final msg = _messageFrom(raw, includeBody: false);
    if (matchesPostaFilter(msg, filter)) out.add(msg);
  }
  return out;
});

final postaDetailProvider =
    FutureProvider.family<PostaMessage?, String>((ref, id) async {
  ref.watch(authControllerProvider);
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null || id.isEmpty) return null;
  final row = await client
      .from('posta_messages')
      .select(
        'id, from_address, from_name, subject, body_text, received_at, status, '
        'cliente_id, match_method, gmail_url, message_id_header, mensaje_id, '
        'clientes(nombre, apellidos, razon_social), '
        'posta_attachments(id, filename, mime, byte_size, storage_path, documento_id, deleted_at)',
      )
      .eq('id', id)
      .eq('tenant_id', tenantId)
      .isFilter('deleted_at', null)
      .maybeSingle();
  if (row == null) return null;
  return _messageFrom(row, includeBody: true);
});

final clientePostaProvider =
    FutureProvider.family<List<PostaMessage>, String>((ref, clienteId) async {
  ref.watch(authControllerProvider);
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return [];
  final rows = await client
      .from('posta_messages')
      .select(
        'id, from_address, from_name, subject, received_at, status, '
        'cliente_id, match_method, gmail_url, message_id_header, mensaje_id, '
        'posta_attachments(id, filename, mime, byte_size, storage_path, documento_id, deleted_at)',
      )
      .eq('tenant_id', tenantId)
      .eq('cliente_id', clienteId)
      .isFilter('deleted_at', null)
      .neq('status', 'ignored')
      .order('received_at', ascending: false)
      .limit(40);
  final out = <PostaMessage>[];
  for (final raw in rows as List) {
    if (raw is! Map) continue;
    out.add(_messageFrom(raw, includeBody: false));
  }
  return out;
});

bool matchesPostaFilter(PostaMessage msg, String filter) {
  return switch (filter) {
    'unassigned' => msg.status == 'unassigned',
    'unfiled' => msg.hasUnfiled && msg.status != 'ignored',
    'attachments' => msg.hasAttachments && msg.status != 'ignored',
    'assigned' => msg.status == 'assigned',
    'all' => msg.status != 'ignored',
    _ => true,
  };
}

Future<void> assignPostaMessage({
  required String messageId,
  required String clienteId,
}) async {
  final client = trySupabaseClient();
  if (client == null) throw StateError('not configured');
  await client.rpc(
    'assign_posta_message',
    params: {'p_message_id': messageId, 'p_cliente_id': clienteId},
  );
}

Future<void> ignorePostaMessage(String messageId) async {
  final client = trySupabaseClient();
  if (client == null) throw StateError('not configured');
  await client.rpc(
    'ignore_posta_message',
    params: {'p_message_id': messageId},
  );
}

Future<void> unassignPostaMessage(String messageId) async {
  final client = trySupabaseClient();
  if (client == null) throw StateError('not configured');
  await client.rpc(
    'unassign_posta_message',
    params: {'p_message_id': messageId},
  );
}

final postaSuggestProvider =
    FutureProvider.family<PostaClienteHit?, String>((ref, messageId) async {
  ref.watch(authControllerProvider);
  final msg = await ref.watch(postaDetailProvider(messageId).future);
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (msg == null || msg.assigned || tenantId == null) return null;
  return suggestPostaCliente(
    tenantId: tenantId,
    email: msg.fromAddress,
    fromName: msg.fromName,
  );
});

class PostaQuickFile {
  const PostaQuickFile({
    required this.clienteId,
    required this.clienteNombre,
    required this.attachment,
    required this.target,
    this.assignHit,
  });

  final String clienteId;
  final String clienteNombre;
  final PostaAttachment attachment;
  final PostaFileTarget target;
  final PostaClienteHit? assignHit;
}

/// Unikátní klient + unikátní blok → jedno tlačítko. Jinak null (dialog).
final postaQuickFileProvider =
    FutureProvider.family<PostaQuickFile?, String>((ref, messageId) async {
  ref.watch(authControllerProvider);
  final msg = await ref.watch(postaDetailProvider(messageId).future);
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (msg == null || tenantId == null || !msg.hasUnfiled) return null;
  if (isPostaNoiseMail(from: msg.fromAddress, subject: msg.subject)) {
    return null;
  }
  PostaClienteHit? hit;
  var clienteId = msg.clienteId;
  var nombre = msg.clienteNombre ?? '';
  if (clienteId == null || clienteId.isEmpty) {
    hit = await suggestPostaCliente(
      tenantId: tenantId,
      email: msg.fromAddress,
      fromName: msg.fromName,
    );
    clienteId = hit?.id;
    nombre = hit?.nombre ?? '';
  }
  if (clienteId == null || clienteId.isEmpty) return null;
  final att = msg.attachments.firstWhere((a) => !a.filed);
  final hints = suggestPostaBloqueKeys(
    filename: att.filename,
    subject: msg.subject ?? '',
    body: msg.bodyText ?? '',
  );
  if (hints.isEmpty) return null;
  final targets = await loadPostaFileTargets(
    clienteId,
    suggestedKeys: hints,
  );
  final target = uniqueSuggestedFileTarget(targets);
  if (target == null) return null;
  return PostaQuickFile(
    clienteId: clienteId,
    clienteNombre: nombre,
    attachment: att,
    target: target,
    assignHit: hit,
  );
});

Future<PostaClienteHit?> suggestPostaCliente({
  required String tenantId,
  required String email,
  String? fromName,
}) async {
  final client = trySupabaseClient();
  if (client == null) return null;
  final raw = await client.rpc(
    'suggest_posta_cliente',
    params: {
      'p_tenant_id': tenantId,
      'p_email': email,
      'p_from_name': fromName,
    },
  );
  final row = _firstMap(raw);
  if (row == null || row['cliente_id'] == null) return null;
  return PostaClienteHit(
    id: '${row['cliente_id']}',
    nombre: '${row['nombre'] ?? ''}'.trim().isEmpty
        ? '—'
        : '${row['nombre']}'.trim(),
    matchMethod: _trimOrNull(row['match_method']),
    auto: row['auto'] == true,
  );
}

Future<List<PostaClienteHit>> searchPostaClientes(String query) async {
  final client = trySupabaseClient();
  final q = query.trim();
  if (client == null || q.isEmpty) return [];
  final hits = await client.rpc(
    'search_clients',
    params: {'p_q': q, 'p_limit': 12},
  );
  final ids = <String>[];
  if (hits is List) {
    for (final raw in hits) {
      if (raw is Map && raw['cliente_id'] != null) {
        ids.add('${raw['cliente_id']}');
      }
    }
  }
  if (ids.isEmpty) return [];
  final rows = await client
      .from('clientes')
      .select(
        'id, nombre, apellidos, razon_social, email, '
        'client_identifiers(kind, value_raw, deleted_at)',
      )
      .inFilter('id', ids)
      .isFilter('deleted_at', null);
  final byId = <String, PostaClienteHit>{};
  for (final raw in rows as List) {
    if (raw is! Map) continue;
    final id = '${raw['id']}';
    byId[id] = PostaClienteHit(
      id: id,
      nombre: _clienteNombre(raw),
      email: _trimOrNull(raw['email']),
      nie: preferredFiscalRawFromRows(raw['client_identifiers']),
    );
  }
  return [
    for (final id in ids)
      if (byId[id] != null) byId[id]!,
  ];
}

Future<List<PostaFileTarget>> loadPostaFileTargets(
  String clienteId, {
  List<String> suggestedKeys = const [],
}) async {
  final client = trySupabaseClient();
  if (client == null) return const [PostaFileTarget(labelKey: 'posta.fileCard')];
  final rows = await client
      .from('bloques')
      .select(
        'id, template_key, status, '
        'expedientes!inner(id, cliente_id, deleted_at, titulo, inmuebles(direccion))',
      )
      .eq('expedientes.cliente_id', clienteId)
      .isFilter('deleted_at', null)
      .isFilter('expedientes.deleted_at', null)
      .neq('status', 'off');
  final blocks = <PostaFileTarget>[];
  for (final raw in rows as List) {
    if (raw is! Map) continue;
    final key = '${raw['template_key'] ?? ''}';
    if (key.isEmpty || key == 'cliente_snapshot') continue;
    BloqueTemplate? template;
    for (final t in compraventaBloques) {
      if (t.key == key) {
        template = t;
        break;
      }
    }
    blocks.add(
      PostaFileTarget(
        labelKey: 'blocks.$key',
        bloqueId: '${raw['id']}',
        templateKey: key,
        requiredDocTypes: template?.requiredDocTypes ?? const [],
        place: _filePlace(raw['expedientes']),
        suggested: suggestedKeys.contains(key),
        expedienteId: _expedienteId(raw['expedientes']),
      ),
    );
  }
  final order = <String, int>{
    for (var i = 0; i < compraventaBloques.length; i++)
      compraventaBloques[i].key: i,
  };
  blocks.sort((a, b) {
    final as = a.suggested ? 0 : 1;
    final bs = b.suggested ? 0 : 1;
    if (as != bs) return as - bs;
    final ao = order[a.templateKey] ?? 99;
    final bo = order[b.templateKey] ?? 99;
    if (ao != bo) return ao - bo;
    return (a.place ?? '').compareTo(b.place ?? '');
  });
  return [
    ...blocks,
    const PostaFileTarget(labelKey: 'posta.fileCard'),
  ];
}

String? _expedienteId(Object? expediente) {
  if (expediente is! Map) return null;
  final id = '${expediente['id'] ?? ''}'.trim();
  return id.isEmpty ? null : id;
}

String? _filePlace(Object? expediente) {
  if (expediente is! Map) return null;
  final inm = expediente['inmuebles'];
  final direccion = inm is Map ? '${inm['direccion'] ?? ''}'.trim() : '';
  if (direccion.isNotEmpty) return direccion;
  final titulo = '${expediente['titulo'] ?? ''}'.trim();
  return titulo.isEmpty ? null : titulo;
}

/// Stáhne přílohu z ingest cesty a uloží ji jako `documentos` u klienta.
Future<void> filePostaAttachment({
  required String tenantId,
  required String clienteId,
  required PostaAttachment attachment,
  required PostaFileTarget target,
  String? createdBy,
}) async {
  final client = trySupabaseClient();
  if (client == null) throw OfficeUploadException('not_configured');
  final bytes = await client.storage.from('documentos').download(
        attachment.storagePath,
      );
  if (bytes.isEmpty) throw OfficeUploadException('empty');
  final name = attachment.filename;
  final tipo = target.isCard
      ? guessDocumentoTipo(
          requiredDocTypes: const [],
          alreadyHave: const {},
          originalName: name,
        )
      : guessDocumentoTipo(
          requiredDocTypes: target.requiredDocTypes,
          alreadyHave: const {},
          originalName: name,
        );
  final path = documentoStoragePath(
    tenantId: tenantId,
    clienteId: clienteId,
    originalName: name,
    bloqueId: target.bloqueId,
  );
  await uploadDocumentoBytes(
    path: path,
    bytes: Uint8List.fromList(bytes),
    originalName: name,
  );
  final docId = await insertDocumentoRow(
    tenantId: tenantId,
    clienteId: clienteId,
    tipo: tipo,
    storagePath: path,
    originalName: name,
    bloqueId: target.bloqueId,
    createdBy: createdBy,
  );
  await client.rpc(
    'mark_posta_attachment_filed',
    params: {
      'p_attachment_id': attachment.id,
      'p_documento_id': docId,
    },
  );
  startExtractInBackground(
    tenantId: tenantId,
    clienteId: clienteId,
    storagePath: path,
    mime: mimeForOfficeFile(name),
    docTipo: tipo,
    bloqueKey: target.templateKey ?? 'cliente_snapshot',
  );
}

Future<String> signedPostaUrl(String storagePath) async {
  final client = trySupabaseClient();
  if (client == null) throw StateError('not configured');
  return client.storage.from('documentos').createSignedUrl(storagePath, 120);
}

PostaMessage _messageFrom(Map raw, {required bool includeBody}) {
  final attachments = <PostaAttachment>[];
  final attRaw = raw['posta_attachments'];
  if (attRaw is List) {
    for (final a in attRaw) {
      if (a is! Map) continue;
      if (a['deleted_at'] != null) continue;
      attachments.add(
        PostaAttachment(
          id: '${a['id']}',
          filename: '${a['filename'] ?? 'file'}',
          storagePath: '${a['storage_path'] ?? ''}',
          mime: _trimOrNull(a['mime']),
          byteSize: int.tryParse('${a['byte_size'] ?? ''}'),
          documentoId: _trimOrNull(a['documento_id']),
        ),
      );
    }
  }
  return PostaMessage(
    id: '${raw['id']}',
    fromAddress: '${raw['from_address'] ?? ''}',
    fromName: _trimOrNull(raw['from_name']),
    subject: _trimOrNull(raw['subject']),
    bodyText: includeBody ? _trimOrNull(raw['body_text']) : null,
    receivedAt: DateTime.tryParse('${raw['received_at']}') ?? DateTime.now(),
    status: '${raw['status'] ?? 'unassigned'}',
    clienteId: _trimOrNull(raw['cliente_id']),
    clienteNombre: _embeddedClienteNombre(raw['clientes']),
    matchMethod: _trimOrNull(raw['match_method']),
    gmailUrl: _trimOrNull(raw['gmail_url']),
    messageIdHeader: _trimOrNull(raw['message_id_header']),
    mensajeId: _trimOrNull(raw['mensaje_id']),
    attachments: attachments,
  );
}

String? _embeddedClienteNombre(Object? raw) {
  if (raw is! Map) return null;
  final n = _clienteNombre(raw);
  return n.isEmpty ? null : n;
}

String _clienteNombre(Map raw) {
  final razon = '${raw['razon_social'] ?? ''}'.trim();
  if (razon.isNotEmpty) return razon;
  return [
    '${raw['nombre'] ?? ''}'.trim(),
    '${raw['apellidos'] ?? ''}'.trim(),
  ].where((s) => s.isNotEmpty).join(' ');
}

String? _trimOrNull(Object? v) {
  final s = '$v'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

Map<String, dynamic>? _firstMap(Object? raw) {
  if (raw is List && raw.isNotEmpty && raw.first is Map) {
    return Map<String, dynamic>.from(raw.first as Map);
  }
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}
