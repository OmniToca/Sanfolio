/// HTML z mailu na čitelný text a bezpečný náhled. Žádný script, žádný layout engine.
library;

final _script = RegExp(r'<script[\s\S]*?</script>', caseSensitive: false);
final _style = RegExp(r'<style[\s\S]*?</style>', caseSensitive: false);
final _comment = RegExp(r'<!--[\s\S]*?-->');
final _tag = RegExp(r'<[^>]+>');
final _br = RegExp(r'<br\s*/?>', caseSensitive: false);
final _blockEnd = RegExp(
  r'</(p|div|tr|h[1-6]|li|blockquote|table|section|article)>',
  caseSensitive: false,
);
final _li = RegExp(r'<li[^>]*>', caseSensitive: false);
final _quote = RegExp(r'<blockquote[^>]*>', caseSensitive: false);
final _anchor = RegExp(
  r'''<a[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)</a>''',
  caseSensitive: false,
);
final _imgAlt = RegExp(
  r'''<img[^>]*alt=["']([^"']*)["'][^>]*>''',
  caseSensitive: false,
);
final _dangerousTag = RegExp(
  r'<(script|iframe|object|embed|form|input|button|link|meta|base|svg)[\s\S]*?>[\s\S]*?</\1>',
  caseSensitive: false,
);
final _dangerousVoid = RegExp(
  r'<(script|iframe|object|embed|form|input|button|link|meta|base)[^>]*>',
  caseSensitive: false,
);
final _onAttr = RegExp(
  r'''\s+on[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)''',
  caseSensitive: false,
);
final _jsUrl = RegExp(
  r'''(href|src)\s*=\s*["']\s*javascript:[^"']*["']''',
  caseSensitive: false,
);

/// HTML → odstavce, odrážky, odkazy. Citace s `>`.
String htmlToReadableText(String html) {
  if (html.trim().isEmpty) return '';
  var s = html.replaceAll('\r\n', '\n');
  s = s.replaceAll(_comment, '');
  s = s.replaceAll(_script, '');
  s = s.replaceAll(_style, '');
  s = s.replaceAll(_br, '\n');
  s = s.replaceAll(_blockEnd, '\n');
  s = s.replaceAll(_li, '• ');
  s = s.replaceAll(_quote, '> ');
  s = s.replaceAllMapped(_anchor, (m) {
    final href = m.group(1) ?? '';
    final label = _decodeEntities(_plain(m.group(2) ?? '')).trim();
    if (label.isEmpty) return href;
    if (label.contains(href) || href.isEmpty) return label;
    return '$label ($href)';
  });
  s = s.replaceAllMapped(_imgAlt, (m) {
    final alt = (m.group(1) ?? '').trim();
    return alt.isEmpty ? ' ' : ' $alt ';
  });
  s = _plain(s);
  s = _decodeEntities(s);
  s = s.replaceAll(RegExp(r'[ \t]+\n'), '\n');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

/// Odstraní skripty a handlery. Zbylé HTML smí do iframe bez allow-scripts.
String sanitizePostaHtml(String html) {
  var s = html.replaceAll(_comment, '');
  s = s.replaceAll(_script, '');
  s = s.replaceAll(_style, '');
  s = s.replaceAll(_dangerousTag, '');
  s = s.replaceAll(_dangerousVoid, '');
  s = s.replaceAll(_onAttr, '');
  s = s.replaceAll(_jsUrl, '');
  s = s.replaceAll(
    RegExp(r'''src\s*=\s*["']\s*data:(?!image/)[^"']*["']''',
        caseSensitive: false),
    '',
  );
  return s.trim();
}

/// Obálka iframe: písmo kanceláře, citace, tabulky, obrázky max. šířka.
String wrapPostaHtml(String sanitized) {
  final body = sanitized.isEmpty ? '<p></p>' : sanitized;
  return '''<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  html,body{margin:0;padding:12px 4px 20px;font:15px/1.5 ui-sans-serif,system-ui,sans-serif;color:#161412;background:#FFFCF8;word-wrap:break-word;}
  a{color:#1B5F59;}
  blockquote{border-left:3px solid #DFD8CC;margin:8px 0;padding:0 12px;color:#6B645C;}
  img{max-width:100%;height:auto;}
  table{border-collapse:collapse;max-width:100%;}
  td,th{border:1px solid #DFD8CC;padding:6px 8px;font-size:14px;}
  p{margin:0 0 10px;}
</style></head><body>$body</body></html>''';
}

String _plain(String s) => s.replaceAll(_tag, ' ').replaceAll(RegExp(r'[ \t]+'), ' ');

String _decodeEntities(String s) {
  return s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");
}
