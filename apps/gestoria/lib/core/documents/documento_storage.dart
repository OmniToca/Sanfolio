import 'dart:math';
import 'dart:typed_data';

import 'package:gestoria_auth/gestoria_auth.dart';

/// Jedna cesta originálu: `{tenant}/{cliente}/{id}_{název}`.
/// PROČ ne `card/` vs `ai/`: stejný sken se jinak uložil dvakrát.
String documentoStoragePath({
  required String tenantId,
  required String clienteId,
  required String originalName,
}) {
  final safe = originalName.replaceAll(RegExp(r'[/\\]'), '_').trim();
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

/// Nahrání originálu. Když INSERT řádku selže, objekt se smaže (orphan).
Future<void> uploadDocumentoBytes({
  required String path,
  required Uint8List bytes,
}) async {
  final client = trySupabaseClient();
  if (client == null) throw StateError('not configured');
  await client.storage.from('documentos').uploadBinary(path, bytes);
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
