import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Blob URL v novém okně — Safari tiskne titulek dokumentu, ne about:srcdoc.
void printHtmlDocument(String html) {
  final blob = web.Blob(
    [html.toJS].toJS,
    web.BlobPropertyBag(type: 'text/html;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final win = web.window.open(url, '_blank');
  if (win == null) {
    final iframe = web.HTMLIFrameElement()
      ..src = url
      ..style.position = 'fixed'
      ..style.width = '0'
      ..style.height = '0'
      ..style.border = '0';
    web.document.body?.append(iframe);
  }
  Timer(const Duration(minutes: 2), () {
    web.URL.revokeObjectURL(url);
  });
}
