import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:http/http.dart' as http;

import 'office_file_pick.dart';

/// SHA-256 hex. Stejné bajty u klienta = jeden papír, ne druhá kopie.
String documentoContentSha256(List<int> bytes) =>
    sha256.convert(bytes).toString();

/// Nový originál: `{tenant}/{cliente}/stoh/{soubor}`.
/// Staré soubory můžou ležet v `{cliente}/` nebo `{cliente}/{bloque}/`.
/// Album je odkaz (`documento_bloques`), ne nová cesta. Žádné `card/` vs `ai/`.
String documentoStoragePath({
  required String tenantId,
  required String clienteId,
  required String originalName,
  String? bloqueId,
  bool stoh = false,
}) {
  // `#` `?` `%` v URL rozbijí Storage. Mezery Safari taky občas spolkne.
  final safe = originalName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final name = safe.isEmpty ? 'file' : safe;
  final ts = DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(16);
  // dart2js: `1 << 32` je 0 (shift jen 32 bitů) → nextInt hodí RangeError.
  final rand =
      Random.secure().nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
  final folder = stoh
      ? '$tenantId/$clienteId/stoh'
      : (bloqueId == null || bloqueId.isEmpty)
          ? '$tenantId/$clienteId'
          : '$tenantId/$clienteId/$bloqueId';
  return '$folder/${ts}_${rand}_$name';
}

/// Cesta patří tenantovi (a klientovi, když je znám).
bool documentoPathInTenant({
  required String path,
  required String tenantId,
  String? clienteId,
}) {
  if (path.contains('..')) return false;
  final prefix = clienteId == null || clienteId.isEmpty
      ? '$tenantId/'
      : '$tenantId/$clienteId/';
  return path.startsWith(prefix);
}

/// Kód do toastu. Žádný stack trace v UI.
class OfficeUploadException implements Exception {
  OfficeUploadException(this.code, {this.status});

  final String code;
  final int? status;

  @override
  String toString() => 'OfficeUploadException($code)';
}

String encodeDocumentoStoragePath(String path) {
  return path.split('/').map(Uri.encodeComponent).join('/');
}

/// Raw POST těla. `uploadBinary` na webu posílá multipart s prázdným filename —
/// Safari to Storage často odmítne a objekt nikdy nevznikne.
Future<void> uploadDocumentoBytes({
  required String path,
  required Uint8List bytes,
  String? originalName,
}) async {
  final client = trySupabaseClient();
  if (client == null) throw OfficeUploadException('not_configured');
  final token = client.auth.currentSession?.accessToken;
  if (token == null || token.isEmpty) {
    throw OfficeUploadException('auth');
  }
  final mime = mimeForOfficeFile(originalName ?? path);
  final uri = Uri.parse(
    '${client.storage.url}/object/documentos/${encodeDocumentoStoragePath(path)}',
  );
  final http.Response res;
  try {
    res = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'apikey': SupabaseConfig.anonKey,
        'Content-Type': mime,
        'x-upsert': 'false',
      },
      body: bytes,
    );
  } on OfficeUploadException {
    rethrow;
  } on Object catch (e) {
    debugPrint('storage network $e');
    throw OfficeUploadException('network');
  }
  if (res.statusCode < 200 || res.statusCode >= 300) {
    debugPrint('storage upload ${res.statusCode} ${res.body}');
    throw OfficeUploadException(
      _codeForHttp(res.statusCode),
      status: res.statusCode,
    );
  }
}

String _codeForHttp(int status) {
  return switch (status) {
    401 || 403 => 'auth',
    413 => 'too_big',
    415 => 'bad_type',
    _ => 'http_$status',
  };
}

/// INSERT `documentos` po uploadu. Když řádek spadne, blob se uklidí.
Future<String> insertDocumentoRow({
  required String tenantId,
  required String clienteId,
  required String tipo,
  required String storagePath,
  required String originalName,
  String? bloqueId,
  String? createdBy,
  String? contentSha256,
  String? inmuebleId,
}) async {
  final client = trySupabaseClient();
  if (client == null) throw OfficeUploadException('not_configured');
  try {
    final inserted = await client
        .from('documentos')
        .insert({
          'tenant_id': tenantId,
          'cliente_id': clienteId,
          'tipo': tipo,
          'storage_path': storagePath,
          'original_name': originalName,
          if (bloqueId != null && bloqueId.isNotEmpty) 'bloque_id': bloqueId,
          if (createdBy != null && createdBy.isNotEmpty) 'created_by': createdBy,
          if (contentSha256 != null && contentSha256.isNotEmpty)
            'content_sha256': contentSha256,
          if (inmuebleId != null && inmuebleId.isNotEmpty)
            'inmueble_id': inmuebleId,
        })
        .select('id')
        .single();
    return '${inserted['id']}';
  } on Object catch (e) {
    debugPrint('documentos insert $e');
    await rollbackDocumentoUpload(storagePath);
    throw OfficeUploadException('db');
  }
}

/// Řádek po nahrání na hromadu. [alreadyExisted] = stejné bajty, blob se nepsal znovu.
class IngestedClienteDocumento {
  const IngestedClienteDocumento({
    required this.id,
    required this.storagePath,
    required this.originalName,
    required this.tipo,
    required this.contentSha256,
    this.alreadyExisted = false,
  });

  final String id;
  final String storagePath;
  final String originalName;
  final String tipo;
  final String contentSha256;
  final bool alreadyExisted;
}

/// Jedna kupa u klienta. Kam patří se řeší až albem, ne druhým souborem.
Future<IngestedClienteDocumento> ingestClienteDocumento({
  required String tenantId,
  required String clienteId,
  required Uint8List bytes,
  required String originalName,
  String tipo = 'other',
  String? createdBy,
  String? inmuebleId,
  bool rejectDuplicate = false,
}) async {
  final client = trySupabaseClient();
  if (client == null) throw OfficeUploadException('not_configured');
  final hash = documentoContentSha256(bytes);
  final resolvedTipo = tipo.trim().isEmpty ? 'other' : tipo.trim();
  final dup = await client
      .from('documentos')
      .select('id, tipo, storage_path, original_name, content_sha256')
      .eq('tenant_id', tenantId)
      .eq('cliente_id', clienteId)
      .eq('content_sha256', hash)
      .isFilter('deleted_at', null)
      .maybeSingle();
  if (dup != null) {
    if (rejectDuplicate) throw OfficeUploadException('duplicate');
    final existingTipo = '${dup['tipo'] ?? 'other'}'.trim();
    final id = '${dup['id']}';
    if (resolvedTipo != 'other' &&
        (existingTipo.isEmpty || existingTipo == 'other')) {
      await client.from('documentos').update({
        'tipo': resolvedTipo,
      }).eq('id', id).eq('tenant_id', tenantId);
    }
    return IngestedClienteDocumento(
      id: id,
      storagePath: '${dup['storage_path'] ?? ''}',
      originalName: '${dup['original_name'] ?? originalName}',
      tipo: resolvedTipo != 'other' &&
              (existingTipo.isEmpty || existingTipo == 'other')
          ? resolvedTipo
          : (existingTipo.isEmpty ? 'other' : existingTipo),
      contentSha256: hash,
      alreadyExisted: true,
    );
  }
  final path = documentoStoragePath(
    tenantId: tenantId,
    clienteId: clienteId,
    originalName: originalName,
    stoh: true,
  );
  await uploadDocumentoBytes(
    path: path,
    bytes: bytes,
    originalName: originalName,
  );
  final id = await insertDocumentoRow(
    tenantId: tenantId,
    clienteId: clienteId,
    tipo: resolvedTipo,
    storagePath: path,
    originalName: originalName,
    createdBy: createdBy,
    contentSha256: hash,
    inmuebleId: inmuebleId,
  );
  return IngestedClienteDocumento(
    id: id,
    storagePath: path,
    originalName: originalName,
    tipo: resolvedTipo,
    contentSha256: hash,
  );
}

/// Odkaz papíru na album. Originál zůstává na hromadě.
Future<void> linkDocumentoBloque({
  required String documentoId,
  required String bloqueId,
  required String tipo,
}) async {
  final client = trySupabaseClient();
  if (client == null) throw OfficeUploadException('not_configured');
  await client.rpc(
    'set_documento_placement',
    params: {
      'p_documento_id': documentoId,
      'p_bloque_id': bloqueId,
      'p_tipo': tipo.trim().isEmpty ? 'other' : tipo.trim(),
      'p_on': true,
    },
  );
}

/// Best-effort úklid blobu bez řádku v `documentos`.
Future<void> rollbackDocumentoUpload(String path) async {
  final client = trySupabaseClient();
  if (client == null) return;
  try {
    await client.storage.from('documentos').remove([path]);
  } on Object {
    // Řádek nevznikl; další pokus nesmí spadnout na úklidu.
  }
}
