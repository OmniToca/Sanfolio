import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'office_file_pick_stub.dart'
    if (dart.library.js_interop) 'office_file_pick_web.dart' as office_dialog;

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

/// Stoh ze šanonu. Víc by extract na pozadí neusnesl najednou.
const officeFileBatchMax = 40;

/// Živý seznam z `<input>` se po `value = ''` vyprázdní. Nejdřív kopie.
List<T> takeIndexedBatch<T>(
  int length,
  T? Function(int index) item, {
  int max = officeFileBatchMax,
}) {
  if (length <= 0) return const [];
  final cap = length > max ? max : length;
  final out = <T>[];
  for (var i = 0; i < cap; i++) {
    final value = item(i);
    if (value != null) out.add(value);
  }
  return out;
}

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

/// Dialog souboru. Web: vlastní input (Safari). Jinak file_picker.
Future<PickedOfficeFile?> pickOfficeFile() async {
  final raw = await office_dialog.openOfficeFileDialog();
  if (raw == null) return null;
  return officeFileFromBytes(raw.bytes, raw.name);
}

/// Více souborů ze šanonu. Prázdné = zrušeno. Nad [officeFileBatchMax] ořízne.
Future<List<PickedOfficeFile>> pickOfficeFiles() async {
  final raw = await office_dialog.openOfficeFilesDialog();
  if (raw == null || raw.isEmpty) return const [];
  final out = <PickedOfficeFile>[];
  for (final f in raw.take(officeFileBatchMax)) {
    out.add(officeFileFromBytes(f.bytes, f.name));
  }
  return out;
}

Future<PickedOfficeFile> officeFileFromPicked(PlatformFile file) async {
  final bytes = await _bytesOf(file);
  return officeFileFromBytes(bytes, file.name, extension: file.extension);
}

/// Kopie na Dart heap — JS ArrayBuffer ze Safari se jinak utrhne před uploadem.
PickedOfficeFile officeFileFromBytes(
  Uint8List? raw,
  String originalName, {
  String? extension,
}) {
  var ext = (extension ?? originalName.split('.').last).toLowerCase();
  if (!officeFileExtensions.contains(ext)) {
    ext = '';
  }
  if (raw == null || raw.isEmpty) {
    throw OfficeFilePickException(OfficeFilePickError.empty);
  }
  final bytes = Uint8List.fromList(raw);
  if (bytes.length > officeFileMaxBytes) {
    throw OfficeFilePickException(OfficeFilePickError.tooBig);
  }
  if (ext.isEmpty) {
    ext = sniffOfficeExtension(bytes) ?? '';
  }
  if (!officeFileExtensions.contains(ext)) {
    throw OfficeFilePickException(OfficeFilePickError.badType);
  }
  var name = originalName.trim();
  if (name.isEmpty) name = 'file.$ext';
  if (!name.toLowerCase().endsWith('.$ext')) {
    name = '$name.$ext';
  }
  return PickedOfficeFile(bytes: bytes, name: name, extension: ext);
}

Future<Uint8List?> _bytesOf(PlatformFile file) async {
  final direct = file.bytes;
  if (direct != null && direct.isNotEmpty) {
    return Uint8List.fromList(direct);
  }
  final stream = file.readStream;
  if (stream == null) return null;
  final out = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    out.add(chunk);
  }
  final bytes = out.takeBytes();
  return bytes.isEmpty ? null : bytes;
}
