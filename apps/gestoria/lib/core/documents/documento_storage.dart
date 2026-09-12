import 'dart:math';
import 'dart:typed_data';

import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'office_file_pick.dart';

/// Jedna cesta originálu: `{tenant}/{cliente}/{id}_{název}`.
/// PROČ ne `card/` vs `ai/`: stejný sken se jinak uložil dvakrát.
String documentoStoragePath({
  required String tenantId,
  required String clienteId,
  required String originalName,
}) {
  // `#` `?` `%` v URL rozbijí Storage. Mezery Safari taky občas spolkne.
  final safe = originalName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final name = safe.isEmpty ? 'file' : safe;
  final ts = DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(16);
  final rand = Random.secure().nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
  return '$tenantId/$clienteId/${ts}_${rand}_$name';
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

/// Nahrání originálu. MIME z názvu — bucket jinak odmítne octet-stream.
Future<void> uploadDocumentoBytes({
  required String path,
  required Uint8List bytes,
  String? originalName,
}) async {
  final client = trySupabaseClient();
  if (client == null) throw StateError('not configured');
  final name = originalName ?? path.split('/').last;
  await client.storage.from('documentos').uploadBinary(
    path,
    Uint8List.fromList(bytes),
    fileOptions: FileOptions(
      contentType: mimeForOfficeFile(name),
      upsert: false,
    ),
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
