import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

import 'cliente_csv.dart';

/// CSV z Excelu. Vlastní input — file_picker na Safari u výběru souboru tahá.
Future<String?> pickClienteCsvText() async {
  final input = HTMLInputElement()
    ..type = 'file'
    ..multiple = false
    ..accept = '.csv,.txt,text/csv';
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
      chosen.complete(files != null && files.length > 0 ? files.item(0) : null);
    }.toJS,
  );

  input.click();
  final file = await chosen.future;
  try {
    if (file == null) return null;
    final buffer = await file.arrayBuffer().toDart;
    final bytes = Uint8List.fromList(buffer.toDart.asUint8List());
    return decodeClienteCsvBytes(bytes);
  } finally {
    input.remove();
  }
}
