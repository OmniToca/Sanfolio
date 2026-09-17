import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

import 'office_file_raw.dart';

/// Záloha, když overlay nejde. Bez `display:none` a bez `cancel` —
/// Safari 17+ při výběru souboru stejně vyšle cancel a spolkl by File.
Future<RawOfficeFile?> openOfficeFileDialog() async {
  final input = HTMLInputElement()
    ..type = 'file'
    ..multiple = false
    ..accept = '.pdf,.jpg,.jpeg,.png,.webp,.heic';
  final s = input.style;
  s.setProperty('opacity', '0');
  s.setProperty('width', '1px');
  s.setProperty('height', '1px');
  s.setProperty('position', 'fixed');
  s.setProperty('left', '0');
  s.setProperty('top', '0');
  document.body?.appendChild(input);

  final chosen = Completer<File?>();
  input.addEventListener(
    'change',
    (Event _) {
      if (chosen.isCompleted) return;
      final files = input.files;
      chosen.complete(
        files != null && files.length > 0 ? files.item(0) : null,
      );
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

Future<List<RawOfficeFile>?> openOfficeFilesDialog() async {
  final input = HTMLInputElement()
    ..type = 'file'
    ..multiple = true
    ..accept = '.pdf,.jpg,.jpeg,.png,.webp,.heic';
  final s = input.style;
  s.setProperty('opacity', '0');
  s.setProperty('width', '1px');
  s.setProperty('height', '1px');
  s.setProperty('position', 'fixed');
  s.setProperty('left', '0');
  s.setProperty('top', '0');
  document.body?.appendChild(input);

  final chosen = Completer<FileList?>();
  input.addEventListener(
    'change',
    (Event _) {
      if (chosen.isCompleted) return;
      chosen.complete(input.files);
    }.toJS,
  );

  input.click();
  final files = await chosen.future;
  try {
    if (files == null || files.length == 0) return null;
    final out = <RawOfficeFile>[];
    final n = files.length;
    for (var i = 0; i < n; i++) {
      final file = files.item(i);
      if (file == null) continue;
      final buffer = await file.arrayBuffer().toDart;
      out.add(
        RawOfficeFile(
          bytes: Uint8List.fromList(buffer.toDart.asUint8List()),
          name: file.name,
        ),
      );
    }
    return out.isEmpty ? null : out;
  } finally {
    input.remove();
  }
}
