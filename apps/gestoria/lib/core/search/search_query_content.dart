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
  'dokumenty',
  'dokument',
  'doklady',
  'dokladu',
  'hromade',
  'hromadě',
  'hromada',
  'stoh',
  'stohu',
  'papir',
  'papír',
  'papiry',
  'papíry',
  'scan',
  'sken',
  'skenu',
  'email',
  'e-mail',
  'mail',
  'posta',
  'pošta',
  'factura',
  'faktura',
  'faktury',
  'bydliste',
  'bydliště',
  'bydli',
  'bydlí',
  'zije',
  'žije',
  'adresa',
  'adrese',
  'ulice',
  'nemovitosti',
  'nemovitostí',
  'nemovitost',
  'finca',
  'systemu',
  'systému',
  'system',
  'systém',
  'ma',
  'má',
  'tam',
  'je',
  'existuje',
  'najdi',
  'najdes',
  'najdeš',
  'ukaz',
  'ukaž',
  'rekni',
  'řekni',
  'povez',
  'pověz',
  'jake',
  'jaké',
  'jaky',
  'jaký',
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
  'document',
  'documents',
  'pile',
  'stack',
  'invoice',
  'address',
  'lives',
  'living',
  'street',
  'show',
  'list',
  'any',
  'some',
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
  'documento',
  'documentos',
  'montón',
  'monton',
  'pila',
  'correo',
  'dirección',
  'direccion',
  'domicilio',
  'calle',
  'vivienda',
  'mostrar',
  'dime',
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
  'dokumente',
  'stapel',
  'rechnung',
  'adresse',
  'strasse',
  'straße',
  'zeige',
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
  'facture',
  'montre',
  'dis',
};

/// Z NL věty nechá jméno / NIE / ulici (stopslova pryč). Stejný záměr jako SQL.
String searchQueryContent(String raw) {
  final parts = <String>[];
  for (final piece in raw.trim().split(RegExp(r'\s+'))) {
    final tok = piece.replaceAll(
      RegExp(r'''^[.,;:!?„“"'()\[\]{}]+|[.,;:!?„“"'()\[\]{}]+$'''),
      '',
    );
    if (tok.length < 2) continue;
    if (_searchStopwords.contains(tok.toLowerCase())) continue;
    parts.add(tok);
  }
  return parts.join(' ');
}

/// NIE/DNI úlomky ve větě — `Y9908856X` i `Y990`.
List<String> searchQueryIdTokens(String raw) {
  final out = <String>{};
  for (final m in RegExp(r'[A-Za-z0-9*]+').allMatches(raw)) {
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

/// CS/ES koncovky pryč — `Renatu` → `Renat` (SQL `search_name_token_ok`).
String searchNameStem(String raw) {
  final n = normalizeSearchText(raw);
  if (n.length < 4) return n;
  final stemmed = n.replaceFirst(
    RegExp(
      r'(ovou|ovi|ych|ami|ach|ech|ove|ovy|ova|ovu|emu|oum|em|ou|um|y|u|e|a|i)$',
    ),
    '',
  );
  return stemmed.length >= 3 ? stemmed : n;
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
  if (content.isNotEmpty) {
    add(content);
    // Soft: jednotlivé tokeny + stemy (Renatu → Renat).
    for (final tok in content.split(RegExp(r'\s+'))) {
      if (tok.length < 2) continue;
      add(tok);
      final stem = searchNameStem(tok);
      if (stem != normalizeSearchText(tok) && stem.length >= 3) {
        add(stem);
      }
    }
  }
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

/// Otázky o hromadě / dokladech (tipo, DNI, factura, e-mail…).
bool looksLikePileDocsQuery(String raw) {
  final n = normalizeSearchText(raw);
  if (n.isEmpty) return false;
  return n.contains('hromad') ||
      n.contains('stoh') ||
      n.contains('dokument') ||
      n.contains('doklad') ||
      n.contains('papir') ||
      n.contains('scan') ||
      n.contains('sken') ||
      n.contains('dni') ||
      n.contains('pasport') ||
      n.contains('pasaporte') ||
      n.contains('factura') ||
      n.contains('faktur') ||
      n.contains('invoice') ||
      n.contains('email') ||
      n.contains('e-mail') ||
      n.contains('correo') ||
      n.contains('posta') ||
      n.contains('mail ') ||
      n.contains(' mail') ||
      n.contains('escritur') ||
      n.contains('listin') ||
      n.contains('poder') ||
      n.contains('iban') ||
      n.contains('pile') ||
      n.contains('document') ||
      n.contains('rechnung') ||
      n.contains('je tam') ||
      n.contains('ma na') ||
      n.contains('má na') ||
      n.contains('ma v') ||
      n.contains('má v');
}

/// Hinty tipo/text pro `search_cliente_documentos` (stejný záměr jako SQL).
List<String> searchDocQueryParts(String raw) {
  final n = normalizeSearchText(raw);
  if (n.isEmpty) return const [];
  final parts = <String>[];
  void add(String s) {
    if (!parts.contains(s)) parts.add(s);
  }

  if (RegExp(r'(dni|nie|pasport|pasaporte|passport|obcans)').hasMatch(n)) {
    add('dni_nie');
    add('pasaporte');
  }
  if (RegExp(r'(factur|faktura|invoice|rechnung|recibo|ucten)').hasMatch(n)) {
    add('factura');
    add('recibo');
  }
  if (RegExp(r'(email|e-mail|mail|correo|posta|gmail|outlook)').hasMatch(n)) {
    add('email');
    add('correo');
    add('mail');
  }
  if (RegExp(r'(escritur|listin|notar|deed)').hasMatch(n)) {
    add('copia_escritura');
  }
  if (RegExp(r'(poder|plna moc|attorney)').hasMatch(n)) {
    add('copia_poder');
  }
  if (RegExp(r'(iban|bankov)').hasMatch(n)) {
    add('justificante_iban');
  }
  if (RegExp(r'(ibi|suma|catastr)').hasMatch(n)) {
    add('recibo_ibi');
  }
  if (RegExp(r'(seguro|pojist|alarm)').hasMatch(n)) {
    add('poliza_seguro');
    add('contrato_alarma');
  }
  if (RegExp(r'(scan|sken|pdf|fotka|foto|papir)').hasMatch(n)) {
    add('scan');
  }
  return parts;
}

/// Seznam hromady bez filtrování tipo (jen „jaké doklady má X“).
bool looksLikeListPileDocsQuery(String raw) {
  if (!looksLikePileDocsQuery(raw)) return false;
  return searchDocQueryParts(raw).isEmpty;
}
