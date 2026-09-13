import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:http/http.dart' as http;

import 'office_file_pick.dart';

/// Jedna cesta originálu: `{tenant}/{cliente}/{bloque}/{soubor}`.
/// Bez bloque (karta) zůstane `{tenant}/{cliente}/{soubor}`.
/// PROČ ne `card/` vs `ai/`: stejný sken se jinak uložil dvakrát.
String documentoStoragePath({
  required String tenantId,
  required String clienteId,
  required String originalName,
  String? bloqueId,
}) {
  // `#` `?` `%` v URL rozbijí Storage. Mezery Safari taky občas spolkne.
  final safe = originalName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final name = safe.isEmpty ? 'file' : safe;
  final ts = DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(16);
  // dart2js: `1 << 32` je 0 (shift jen 32 bitů) → nextInt hodí RangeError.
  final rand =
      Random.secure().nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
  final folder = (bloqueId == null || bloqueId.isEmpty)
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
