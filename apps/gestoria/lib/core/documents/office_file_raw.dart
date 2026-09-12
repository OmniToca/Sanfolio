import 'dart:typed_data';

/// Výstup dialogu před MIME/limitem. Žádný import na pick — ať web/stub nejsou cyklus.
class RawOfficeFile {
  const RawOfficeFile({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}
