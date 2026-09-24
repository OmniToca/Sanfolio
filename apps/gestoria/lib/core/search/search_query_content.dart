import 'normalize_search_text.dart';

bool _looksLikeNieToken(String tok) {
  return RegExp(r'^[XYZ][0-9*]{7}[A-Z]$').hasMatch(tok) ||
      RegExp(r'^[0-9*]{8}[A-Z]$').hasMatch(tok);
}

/// Stopslova CS/ES/EN/DE/FR — musí sedět s SQL `search_query_content`.
const _searchStopwords = {
  'jak',
  'se',
  'jsem',
  'jsme',
  'jste',
  'jsou',
  'mam',
  'mame',
  'máme',
  'mate',
  'máte',
  'nejaky',
  'nejaka',
  'nějaký',
  'nějaká',
  'nejake',
  'nějaké',
  'klient',
  'klienta',
  'klienti',
  'klienty',
  'klientu',
  'klientů',
  'nasi',
  'naši',
  'nase',
  'naše',
  'jmenuji',
  'jmenuje',
  'jmenují',
  'jmenovat',
  'jmeno',
  'jméno',
  'jménem',
  'nie',
  'dni',
  'nif',
  'cif',
  'pas',
  'pasport',
  'doklad',
  'soubor',
  'prilozte',
  'přiložte',
  'kolik',
  'kde',
  'kdo',
  'co',
  'pro',
  'prosim',
  'prosím',
  'dekuji',
  'děkuji',
  'dal',
  'dál',
  'jeho',
  'jeji',
  'její',
  'jejich',
  'neznam',
  'neznám',
  'podle',
  'dokumentu',
  'dokumentů',
  'hromade',
  'hromadě',
  'nemovitosti',
  'nemovitostí',
  'nemovitost',
  'systemu',
  'systému',
  'system',
  'systém',
  'the',
  'an',
  'and',
  'or',
  'of',
  'for',
  'with',
  'from',
  'our',
  'my',
  'your',
  'client',
  'clients',
  'customer',
  'customers',
  'name',
  'named',
  'called',
  'find',
  'search',
  'who',
  'what',
  'how',
  'many',
  'have',
  'has',
  'is',
  'are',
  'do',
  'does',
  'we',
  'you',
  'el',
  'la',
  'los',
  'las',
  'un',
  'una',
  'de',
  'del',
  'con',
  'por',
  'para',
  'nuestro',
  'nuestra',
  'cliente',
  'clientes',
  'nombre',
  'llamado',
  'buscar',
  'quien',
  'qué',
  'que',
  'cuanto',
  'cuántos',
  'tenemos',
  'tiene',
  'hay',
  'der',
  'die',
  'das',
  'und',
  'oder',
  'mit',
  'von',
  'für',
  'unser',
  'kunde',
  'kunden',
  'namens',
  'suchen',
  'wer',
  'wie',
  'was',
  'haben',
  'hat',
  'ist',
  'sind',
  'le',
  'les',
  'des',
  'du',
  'au',
  'aux',
  'notre',
  'nom',
  'appeler',
  'chercher',
  'qui',
  'quoi',
  'combien',
  'avons',
  'est',
  'sont',
};

/// Z NL věty nechá jméno / NIE (stopslova pryč). Stejný záměr jako SQL.
String searchQueryContent(String raw) {
  final parts = <String>[];
  for (final piece in raw.trim().split(RegExp(r'\s+'))) {
    final tok = piece.replaceAll(RegExp(r'''^[.,;:!?„“"'()\[\]{}]+|[.,;:!?„“"'()\[\]{}]+$'''), '');
    if (tok.length < 2) continue;
    if (_searchStopwords.contains(tok.toLowerCase())) continue;
    parts.add(tok);
  }
  return parts.join(' ');
}

/// NIE/DNI úlomky ve větě — `Y9908856X` i `Y990`.
List<String> searchQueryIdTokens(String raw) {
  final out = <String>{};
  for (final m in RegExp(r"[A-Za-z0-9*]+").allMatches(raw)) {
    final tok = m.group(0)!.toUpperCase();
    if (tok.length < 4) continue;
    final nieFull = RegExp(r'^[XYZ][0-9*]{7}[A-Z]$').hasMatch(tok) ||
        RegExp(r'^[0-9*]{8}[A-Z]$').hasMatch(tok);
    final niePrefix = RegExp(r'^[XYZ][0-9*]{3,}$').hasMatch(tok) ||
        RegExp(r'^[0-9*]{5,}$').hasMatch(tok);
    if (nieFull || niePrefix || _looksLikeNieToken(tok)) {
      out.add(tok);
    }
  }
  return out.toList();
}

/// Dotazy, které dávají smysl pro `search_clients` (ne celá věta).
List<String> searchClientQueries(String raw) {
  final q = raw.trim();
  if (q.isEmpty) return const [];
  final out = <String>[];
  void add(String s) {
    final t = s.trim();
    if (t.length < 2) return;
    if (out.any((e) => e.toLowerCase() == t.toLowerCase())) return;
    out.add(t);
  }

  for (final id in searchQueryIdTokens(q)) {
    add(id);
  }
  final content = searchQueryContent(q);
  if (content.isNotEmpty) add(content);
  // Krátký čistý dotaz (jen jméno) nech také celý.
  if (!q.contains(' ') && content.isEmpty) add(q);
  if (out.isEmpty) add(q);
  return out;
}

/// „jaci klienti / naši klienti / list clients“ — ne search, ale seznam.
bool looksLikeListClientsQuery(String raw) {
  final n = normalizeSearchText(raw);
  if (n.isEmpty) return false;
  final asksList = n.contains('klient') ||
      n.contains('client') ||
      n.contains('kunde') ||
      n.contains('cliente');
  if (!asksList) return false;
  final hasNameOrId = searchQueryContent(raw).isNotEmpty ||
      searchQueryIdTokens(raw).isNotEmpty;
  if (hasNameOrId) return false;
  return n.contains('jmen') ||
      n.contains('nasi') ||
      n.contains('nase') ||
      n.contains('seznam') ||
      n.contains('vsechn') ||
      n.contains('všech') ||
      n.contains('system') ||
      n.contains('list') ||
      n.contains('all ') ||
      n.contains('our ') ||
      n.contains('tenemos') ||
      n.contains('nuestros') ||
      n.contains('haben wir') ||
      n.contains('avons');
}
