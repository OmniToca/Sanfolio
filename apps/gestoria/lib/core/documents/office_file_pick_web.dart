import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

import 'office_file_raw.dart';

/// Safari: file_picker sundá `<input>` hned po click — File pak nejde dočíst
/// a Storage nic nedostane. Input držíme, dokud `arrayBuffer()` neskončí.
Future<RawOfficeFile?> openOfficeFileDialog() async {
  final input = HTMLInputElement()
    ..type = 'file'
    ..multiple = false
    ..accept = '.pdf,.jpg,.jpeg,.png,.webp,.heic';
  input.style.display = 'none';
  document.body?.appendChild(input);

  final chosen = Completer<File?>();
  void finish(File? file) {
    if (!chosen.isCompleted) chosen.complete(file);
  }

  input.addEventListener(
    'change',
    (Event _) {
      final files = input.files;
      finish(
        files != null && files.length > 0 ? files.item(0) : null,
      );
    }.toJS,
  );
  input.addEventListener(
    'cancel',
    (Event _) {
      finish(null);
    }.toJS,
  );

  input.click();
  final file = await chosen.future;
  try {
    if (file == null) return null;
    final buffer = await file.arrayBuffer().toDart;
    return RawOfficeFile(
      bytes: Uint8List.fromList(buffer.toDart.asUint8List()),
      name: file.name,
    );
  } finally {
    input.remove();
  }
}
