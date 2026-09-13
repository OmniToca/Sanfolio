import 'package:web/web.dart' as web;

/// Stažení CSV v prohlížeči. Účetní export knihy, ne PGC.
void saveCsvFile(String filename, String csv) {
  final encoded = Uri.encodeComponent(csv);
  final a = web.document.createElement('a') as web.HTMLAnchorElement;
  a.href = 'data:text/csv;charset=utf-8,$encoded';
  a.download = filename;
  web.document.body?.appendChild(a);
  a.click();
  a.remove();
}
