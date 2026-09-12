import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// PDF a fotky, které bucket `documentos` přijme. HEIC z iPhonu taky.
const officeFileExtensions = <String>[
  'pdf',
  'jpg',
  'jpeg',
  'png',
  'webp',
  'heic',
];

/// 32 MB = limit bucketu po 0030. Větší facturas PDF dřív tichý fail.
const officeFileMaxBytes = 33554432;

class PickedOfficeFile {
  const PickedOfficeFile({
    required this.bytes,
    required this.name,
    this.extension,
  });

  final Uint8List bytes;
  final String name;
  final String? extension;
}

enum OfficeFilePickError { cancelled, empty, tooBig, badType }

class OfficeFilePickException implements Exception {
  OfficeFilePickException(this.code);
  final OfficeFilePickError code;
}

String officePickErrorI18n(OfficeFilePickError code) {
  return switch (code) {
    OfficeFilePickError.tooBig => 'folder.fileTooBig',
    OfficeFilePickError.badType => 'folder.fileType',
    OfficeFilePickError.empty => 'folder.fileEmpty',
    OfficeFilePickError.cancelled => 'folder.uploadError',
  };
}

/// MIME z přípony. Storage i extract podle toho poznají PDF vs. fotku.
String mimeForOfficeFile(String name, {String? extension}) {
  final e = (extension ?? name.split('.').last).toLowerCase();
  return switch (e) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'pdf' => 'application/pdf',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    _ => 'image/jpeg',
  };
}

/// Magic bytes, když Safari/e-mail nedá příponu (Factura bez .pdf).
String? sniffOfficeExtension(Uint8List bytes) {
  if (bytes.length >= 5 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46) {
    return 'pdf';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47) {
    return 'png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'webp';
  }
  return null;
}

/// Dialog souboru. Safari: jen FileReader (`withData`), ne stream —
/// `withReadStream` na webu byty vůbec nenačte.
Future<PickedOfficeFile?> pickOfficeFile() async {
  final picked = await FilePicker.platform.pickFiles(
    withData: true,
    type: FileType.any,
  );
  if (picked == null || picked.files.isEmpty) return null;
  return officeFileFromPicked(picked.files.first);
}

Future<PickedOfficeFile> officeFileFromPicked(PlatformFile file) async {
  var ext = (file.extension ?? file.name.split('.').last).toLowerCase();
  if (!officeFileExtensions.contains(ext)) {
    ext = '';
  }
  final bytes = await _bytesOf(file);
  if (bytes == null || bytes.isEmpty) {
    throw OfficeFilePickException(OfficeFilePickError.empty);
  }
  if (bytes.length > officeFileMaxBytes) {
    throw OfficeFilePickException(OfficeFilePickError.tooBig);
  }
  if (ext.isEmpty) {
    ext = sniffOfficeExtension(bytes) ?? '';
  }
  if (!officeFileExtensions.contains(ext)) {
    throw OfficeFilePickException(OfficeFilePickError.badType);
  }
  var name = file.name.trim();
  if (name.isEmpty) name = 'file.$ext';
  if (!name.toLowerCase().endsWith('.$ext')) {
    name = '$name.$ext';
  }
  return PickedOfficeFile(bytes: bytes, name: name, extension: ext);
}

Future<Uint8List?> _bytesOf(PlatformFile file) async {
  final direct = file.bytes;
  if (direct != null && direct.isNotEmpty) return direct;
  final stream = file.readStream;
  if (stream == null) return null;
  final out = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    out.add(chunk);
  }
  final bytes = out.takeBytes();
  return bytes.isEmpty ? null : bytes;
}
