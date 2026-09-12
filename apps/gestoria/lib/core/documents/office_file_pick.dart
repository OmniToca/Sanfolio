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
    OfficeFilePickError.empty || OfficeFilePickError.cancelled =>
      'folder.uploadError',
  };
}

/// Dialog souboru. Safari občas nedá `bytes` — čteme i stream.
Future<PickedOfficeFile?> pickOfficeFile() async {
  final picked = await FilePicker.platform.pickFiles(
    withData: true,
    withReadStream: true,
    type: FileType.custom,
    allowedExtensions: officeFileExtensions,
  );
  if (picked == null || picked.files.isEmpty) return null;
  return officeFileFromPicked(picked.files.first);
}

Future<PickedOfficeFile> officeFileFromPicked(PlatformFile file) async {
  final ext = (file.extension ?? file.name.split('.').last).toLowerCase();
  if (!officeFileExtensions.contains(ext)) {
    throw OfficeFilePickException(OfficeFilePickError.badType);
  }
  final bytes = await _bytesOf(file);
  if (bytes == null || bytes.isEmpty) {
    throw OfficeFilePickException(OfficeFilePickError.empty);
  }
  if (bytes.length > officeFileMaxBytes) {
    throw OfficeFilePickException(OfficeFilePickError.tooBig);
  }
  return PickedOfficeFile(bytes: bytes, name: file.name, extension: ext);
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
