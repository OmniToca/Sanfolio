import 'dart:convert';
import 'dart:typed_data';

/// PNG z `facturas.sif_qr_url` (data-URI nebo holé base64). HTTPS odkaz není obrázek.
Uint8List? sifQrPngBytes(String? stored) {
  final s = (stored ?? '').trim();
  if (s.isEmpty) return null;
  if (RegExp(r'^https?:\/\/', caseSensitive: false).hasMatch(s)) return null;
  const prefix = 'data:image/png;base64,';
  final payload = s.startsWith(prefix)
      ? s.substring(prefix.length)
      : (s.startsWith('data:') ? null : s.replaceAll(RegExp(r'\s'), ''));
  if (payload == null || payload.isEmpty) return null;
  try {
    return base64Decode(payload);
  } on FormatException {
    return null;
  }
}
