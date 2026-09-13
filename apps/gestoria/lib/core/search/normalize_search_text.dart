/// Fold diakritiky na ASCII. Musí sedět s `public.normalize_search_text`.
/// Jméno sem, ne do `normalize_id` (ten smaže mezery).
String normalizeSearchText(String raw) {
  const from =
      'áàäâãåéèëêíìïîóòöôõúùüûýÿñçčďěňřšťůžÁÀÄÂÃÅÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÝŸÑÇČĎĚŇŘŠŤŮŽ';
  const to =
      'aaaaaaeeeeiiiiooooouuuuyynccdenrstuzAAAAAAEEEEIIIIOOOOOUUUUYYNCCDENRSTUZ';
  final buf = StringBuffer();
  for (final rune in raw.trim().toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final i = from.indexOf(ch);
    buf.write(i >= 0 ? to[i] : ch);
  }
  return buf.toString();
}

/// Celý řetězec, nebo každé slovo (AND). Stejné pravidlo jako SQL `search_name_matches`.
bool searchNameMatches(String haystack, String query) {
  final hay = normalizeSearchText(haystack);
  final q = normalizeSearchText(query);
  if (q.isEmpty || hay.isEmpty) return false;
  if (hay.contains(q)) return true;
  var seen = false;
  for (final tok in q.split(RegExp(r'\s+'))) {
    if (tok.length < 2) continue;
    seen = true;
    if (!hay.contains(tok)) return false;
  }
  return seen;
}
