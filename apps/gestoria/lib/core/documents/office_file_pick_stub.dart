import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'office_file_raw.dart';

/// VM / testy. Web má vlastní input — file_picker tam maže DOM dřív, než Safari dočte soubor.
Future<RawOfficeFile?> openOfficeFileDialog() async {
  final picked = await FilePicker.platform.pickFiles(
    withData: true,
    type: FileType.any,
  );
  if (picked == null || picked.files.isEmpty) return null;
  final file = picked.files.first;
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) {
    return RawOfficeFile(bytes: Uint8List(0), name: file.name);
  }
  return RawOfficeFile(bytes: Uint8List.fromList(bytes), name: file.name);
}
