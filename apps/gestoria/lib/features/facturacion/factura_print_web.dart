import 'package:web/web.dart' as web;

/// Nové okno s A4 HTML — Safari tiskne dokument, ne shell Sanfolia.
void printHtmlDocument(String html) {
  final iframe = web.HTMLIFrameElement()
    ..setAttribute('srcdoc', html)
    ..style.position = 'fixed'
    ..style.width = '0'
    ..style.height = '0'
    ..style.border = '0';
  web.document.body?.append(iframe);
  iframe.onLoad.listen((_) {
    iframe.contentWindow?.print();
  });
}
