import 'documento_fields.dart';
import 'extract_text.dart';

/// Notářská compraventa: první compareciente je skoro vždy prodávající.
bool looksLikeEscrituraText(String text) {
  final t = text.toLowerCase();
  final deed = t.contains('escritura') ||
      t.contains('compraventa') ||
      t.contains('notario') ||
      t.contains('comparecen');
  final parties = t.contains('vender') ||
      t.contains('vendedor') ||
      t.contains('comprar') ||
      t.contains('comprador');
  return deed && parties;
}

String normalizeNie(String raw) {
  return raw.toUpperCase().replaceAll(RegExp(r'[\s\-\./]'), '');
}

class DeedPerson {
  const DeedPerson({
    required this.nie,
    required this.name,
    required this.index,
  });

  final String nie;
  final String name;
  final int index;

  String get label {
    if (name.isEmpty) return nie;
    return '$name ($nie)';
  }
}

/// Návrh řádku `inmueble_titulares`. Guardar zapisuje, AI ne.
class ProposedTitular {
  const ProposedTitular({
    required this.nombre,
    required this.nieRaw,
    required this.nieNormalized,
    required this.lado,
    required this.cuotaBps,
  });

  final String nombre;
  final String nieRaw;
  final String nieNormalized;
  final String lado;
  final int cuotaBps;
}

/// 50 % = 5000. Zbytek na posledního, ať součet živých comprador je 10000.
List<int> splitCuotaBps(int n) {
  if (n <= 0) return const [];
  final base = 10000 ~/ n;
  final rem = 10000 - base * n;
  return [for (var i = 0; i < n; i++) base + (i == n - 1 ? rem : 0)];
}

String sharePercentFromBps(int cuotaBps) {
  final p = (cuotaBps / 100).round();
  if (p < 1) return '1';
  if (p > 100) return '100';
  return '$p';
}

int? cuotaBpsFromSharePercent(String raw) {
  final n = int.tryParse(raw.trim());
  if (n == null || n < 1 || n > 100) return null;
  return n * 100;
}

List<ProposedTitular> proposeTitularesFromDeed(DeedFacts facts) {
  return [
    ..._proposedSide(facts.buyers, 'comprador'),
    ..._proposedSide(facts.sellers, 'vendedor'),
  ];
}

List<ProposedTitular> _proposedSide(List<DeedPerson> people, String lado) {
  if (people.isEmpty) return const [];
  final parts = splitCuotaBps(people.length);
  return [
    for (var i = 0; i < people.length; i++)
      ProposedTitular(
        nombre: people[i].name.trim().isEmpty
            ? people[i].nie
            : people[i].name.trim(),
        nieRaw: people[i].nie,
        nieNormalized: normalizeNie(people[i].nie),
        lado: lado,
        cuotaBps: parts[i],
      ),
  ];
}

/// Unique NIE v tenantovi. Bez NIE jen jméno ke složce, nikdy nová karta.
String? matchTitularClienteId({
  required ProposedTitular row,
  required Map<String, String> nieToClienteId,
  String? folderClienteId,
  String? folderNombre,
}) {
  final nie = row.nieNormalized;
  if (nie.isNotEmpty) return nieToClienteId[nie];
  final folder = folderClienteId?.trim() ?? '';
  final name = folderNombre?.trim() ?? '';
  if (folder.isEmpty || name.isEmpty) return null;
  if (namesLikelyMatch(name, row.nombre)) return folder;
  return null;
}

/// Kupující s NIE bez karty. Složka a prodávající se nezakládají znovu.
bool titularNeedsCoOwnerCard({
  required bool isComprador,
  required String? clienteId,
  required String nieNormalized,
}) {
  if (!isComprador) return false;
  if (nieNormalized.trim().isEmpty) return false;
  final linked = (clienteId ?? '').trim();
  return linked.isEmpty || linked == 'null';
}

String identifierKindFromNormalized(String normalized) {
  final n = normalized.trim().toUpperCase();
  if (RegExp(r'^[XYZ][0-9*]{7}[A-Z]$').hasMatch(n)) return 'nie';
  if (RegExp(r'^[0-9*]{8}[A-Z]$').hasMatch(n)) return 'dni';
  if (RegExp(r'^[A-HJ-NP-SUVW][0-9*]{7}[0-9A-J]$').hasMatch(n)) {
    return 'nif';
  }
  return 'other';
}

/// Fakta z listiny — všichni, ne první pas. Pro 210, plusvalía i hledání v kanceláři.
class DeedFacts {
  const DeedFacts({
    this.sellers = const [],
    this.buyers = const [],
    this.representatives = const [],
    this.notary,
    this.protocol,
    this.address,
    this.cadastral,
    this.parcela,
    this.registry,
    this.lawyer,
    this.salePrice,
    this.referenceValue,
  });

  final List<DeedPerson> sellers;
  final List<DeedPerson> buyers;
  final List<DeedPerson> representatives;
  final String? notary;
  final int? protocol;
  final String? address;
  final String? cadastral;
  final String? parcela;
  final String? registry;
  final String? lawyer;
  final String? salePrice;
  final String? referenceValue;
}

final _deedNie = RegExp(
  r'\b([XYZ])\s*-?\s*(\d{7})\s*-?\s*([A-Z])\b',
  caseSensitive: false,
);
/// D. / Dª na hranici slova. Bez toho `Nad Kneznou` vypadá jako „D. Kneznou“.
final _dName = RegExp(
  r'(?:^|[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ])(?:D[ªº]\.?|D\.|Doña|Don)\s+'
  r'([A-ZÁÉÍÓÚÜÑ][A-ZÁÉÍÓÚÜÑa-záéíóúüñ\.\-\s]{2,80}?)'
  r'(?:,|\n|nacida|nacido|mayor|con |de soltera)',
  caseSensitive: false,
);
final _euroParen = RegExp(
  r'\((\d{1,3}(?:\.\d{3})*(?:,\d{2})?|\d+(?:,\d{2})?)\s*€\)',
);

/// Lidi s NIE. U „respectivamente“ se jména párují v pořadí, ne poslední Dª ke všem.
List<DeedPerson> deedPeople(String text) {
  final out = <DeedPerson>[];
  for (final m in _deedNie.allMatches(text)) {
    final nie = '${m.group(1)}${m.group(2)}${m.group(3)}'.toUpperCase();
    if (!looksLikeNie(nie)) continue;
    final from = m.start - 800 < 0 ? 0 : m.start - 800;
    final window = text.substring(from, m.start);
    String name = '';
    for (final n in _dName.allMatches(window)) {
      final cand = _tidyName(n.group(1) ?? '');
      if (looksLikeDeedPersonName(cand)) name = cand;
    }
    out.add(DeedPerson(nie: nie, name: name, index: m.start));
  }
  return _pairRespectivamente(out, text);
}

DeedFacts extractDeedFacts(String text) {
  final people = deedPeople(text);
  final lower = text.toLowerCase();
  final sellAt = _indexOfAny(lower, const ['para vender', 'parte vendedora']);
  final buyAt = _indexOfAny(lower, const [
    'para comprar',
    'parte compradora',
  ]);
  final interpAt = _indexOfAny(lower, const ['intérprete', 'interprete']);
  final intervienen = lower.indexOf('intervienen');
  final exponen = _indexOfAny(lower, const ['exponen:', 'otorgan:']) ??
      lower.length;
  final interpEnd = interpAt == null
      ? null
      : (intervienen > interpAt ? intervienen : interpAt + 800);

  bool skipInterp(DeedPerson p) {
    if (interpAt == null || interpEnd == null) return false;
    return p.index >= interpAt && p.index < interpEnd;
  }

  final sellers = [
    for (final p in people)
      if (!skipInterp(p) &&
          (sellAt == null || p.index >= sellAt) &&
          (buyAt == null || p.index < buyAt))
        p,
  ];

  final reprAt = lower.indexOf('representaci');
  final represented = [
    for (final p in people)
      if (!skipInterp(p) &&
          reprAt >= 0 &&
          p.index > reprAt &&
          p.index < exponen)
        p,
  ];
  final afterBuy = [
    for (final p in people)
      if (!skipInterp(p) && buyAt != null && p.index > buyAt && p.index < exponen)
        p,
  ];
  final buyers = represented.isNotEmpty
      ? represented
      : [
          for (final p in afterBuy)
            if (!sellers.any((s) => s.nie == p.nie)) p,
        ];
  final representatives = [
    for (final p in afterBuy)
      if (represented.isNotEmpty &&
          !represented.any((b) => b.nie == p.nie) &&
          !skipInterp(p))
        p,
  ];

  return DeedFacts(
    sellers: _uniqueNie(sellers),
    buyers: _uniqueNie(buyers),
    representatives: _uniqueNie(representatives),
    notary: _deedNotary(text),
    protocol: spanishDeedNumber(text),
    address: _deedAddress(text),
    cadastral: _deedCadastral(text),
    parcela: _deedParcela(text),
    registry: _deedRegistry(text),
    lawyer: _deedLawyer(text),
    salePrice: _deedSalePrice(text),
    referenceValue: _deedReferenceValue(text),
  );
}

String formatDeedParties(List<DeedPerson> people) {
  return [for (final p in people) p.label].join('; ');
}

/// LLM jinak čte jen začátek. Pošleme strany, finca, cenu i právníka.
String escrituraLlmFocus(String text, {int head = 4500, int chunk = 5000}) {
  if (text.length <= head + 2000) return text;
  final lower = text.toLowerCase();
  final buf = StringBuffer(
    text.substring(0, text.length < head ? text.length : head),
  );
  void add(String label, List<String> marks, int size) {
    final at = _indexOfAny(lower, marks);
    if (at == null) return;
    final end = (at + size > text.length) ? text.length : at + size;
    buf.write('\n\n--- $label ---\n');
    buf.write(text.substring(at, end));
  }

  add('Comprador', const [
    'para comprar',
    'parte compradora',
    'en nombre y representaci',
  ], chunk);
  add('Finca', const [
    'exponen:',
    'urbana',
    'referencia catastral',
  ], 4000);
  add('Precio', const [
    'precio de esta compraventa',
    'es precio de',
    'otorgan:',
  ], 3500);
  add('Abogado', const ['abogad', 'letrado', 'despacho profesional'], 2500);
  add('Registro', const ['registro de la propiedad'], 2000);
  return buf.toString();
}

/// Doplní strany, cenu a finca. Klient kanceláře je jeden z nich, ne jediný.
Map<String, String> alignDeedFieldsToCliente({
  required Map<String, String> fields,
  required String bodyText,
  String? clienteNombre,
  String? clienteNie,
}) {
  if (!looksLikeEscrituraText(bodyText)) return fields;
  final facts = extractDeedFacts(bodyText);
  final next = Map<String, String>.from(fields);
  if (facts.sellers.isNotEmpty) {
    next['fields.sellers'] = formatDeedParties(facts.sellers);
    next['fields.seller'] = facts.sellers.first.name;
    next['fields.sellerNie'] = facts.sellers.first.nie;
  }
  if (facts.buyers.isNotEmpty) {
    next['fields.buyers'] = formatDeedParties(facts.buyers);
  }
  if (facts.representatives.isNotEmpty) {
    next['fields.attorney'] = formatDeedParties(facts.representatives);
  }
  if (facts.notary != null) next['fields.notary'] = facts.notary!;
  if (facts.protocol != null) next['fields.protocol'] = '${facts.protocol}';
  if (facts.address != null) next['fields.address'] = facts.address!;
  if (facts.cadastral != null) next['fields.cadastral'] = facts.cadastral!;
  if (facts.parcela != null) next['fields.parcela'] = facts.parcela!;
  if (facts.registry != null) next['fields.registry'] = facts.registry!;
  if (facts.lawyer != null) next['fields.lawyer'] = facts.lawyer!;
  if (facts.salePrice != null) next['fields.salePrice'] = facts.salePrice!;
  if (facts.referenceValue != null) {
    next['fields.referenceValue'] = facts.referenceValue!;
  }

  final client = pickDeedClient(
    facts: facts,
    clienteNombre: clienteNombre,
    clienteNie: clienteNie,
  );
  final cardName = (clienteNombre ?? '').trim();
  if (client != null) {
    next['fields.nie'] = client.nie;
    next['fields.nombre'] = cardName.isNotEmpty ? cardName : client.name;
  } else if (facts.buyers.isNotEmpty) {
    final b = facts.buyers.first;
    next['fields.nie'] = b.nie;
    if (b.name.isNotEmpty) next['fields.nombre'] = b.name;
  }

  for (final k in const [
    'fields.expiry',
    'fields.issued',
    'fields.nationality',
    'fields.docNumber',
    'fields.tel',
  ]) {
    next.remove(k);
  }
  return next;
}

/// Žlutý návrh bere strany z přepisu, ne z LLM (Kneznou ≠ kupující).
Map<String, String> displayDocumentoFields({
  required Map<String, String> fields,
  String? bodyText,
  String? clienteNombre,
  String? clienteNie,
}) {
  final fromDoc = (bodyText ?? '').trim();
  final fromFields = (fields['body_text'] ?? '').trim();
  final body = fromDoc.isNotEmpty ? fromDoc : fromFields;
  if (body.isEmpty) return fields;
  return alignDeedFieldsToCliente(
    fields: fields,
    bodyText: body,
    clienteNombre: clienteNombre,
    clienteNie: clienteNie,
  );
}

DeedPerson? pickDeedClient({
  required DeedFacts facts,
  String? clienteNombre,
  String? clienteNie,
}) {
  final pool = [...facts.buyers, ...facts.sellers, ...facts.representatives];
  if (pool.isEmpty) return null;
  final wantNie = (clienteNie ?? '').trim().isEmpty
      ? null
      : normalizeNie(clienteNie!);
  if (wantNie != null) {
    for (final p in pool) {
      if (p.nie == wantNie) return p;
    }
  }
  final wantName = (clienteNombre ?? '').trim();
  if (wantName.isNotEmpty) {
    for (final p in pool) {
      if (p.name.isNotEmpty && namesLikelyMatch(wantName, p.name)) return p;
    }
  }
  return facts.buyers.isNotEmpty ? facts.buyers.first : pool.first;
}

/// Červená jen když na listině není karta. Prodávající ani zmocněnec stačí.
bool documentFitsCliente({
  required String cardName,
  String? cardNie,
  required Map<String, String> fields,
}) {
  final blob = [
    fields['fields.nombre'],
    fields['fields.nie'],
    fields['fields.buyers'],
    fields['fields.sellers'],
    fields['fields.seller'],
    fields['fields.sellerNie'],
    fields['fields.attorney'],
  ].whereType<String>().join(' ');
  final want = (cardNie ?? '').trim().isEmpty ? null : normalizeNie(cardNie!);
  if (want != null && blob.toUpperCase().replaceAll(RegExp(r'[\s\-\./]'), '').contains(want)) {
    return true;
  }
  if (cardName.trim().isEmpty) return true;
  return namesLikelyMatch(cardName, blob);
}

/// Číslo listiny nahoře (DOS MIL CIENTO DIECISÉIS = 2116), ne rok v dědické doložce.
int? spanishDeedNumber(String text) {
  final head = text.length < 900 ? text : text.substring(0, 900);
  final m = RegExp(
    r'N[ÚU]MERO\s+([A-ZÁÉÍÓÚÜÑ\s]+)',
    caseSensitive: false,
  ).firstMatch(head);
  if (m == null) return null;
  final n = parseSpanishInt(m.group(1)!);
  if (n == null || n < 1 || n > 99999) return null;
  return n;
}

int? parseSpanishInt(String raw) {
  var total = 0;
  var current = 0;
  for (final w in _foldEs(raw).split(RegExp(r'[^a-z]+'))) {
    if (w.isEmpty || w == 'y') continue;
    if (w == 'mil') {
      current = (current == 0 ? 1 : current) * 1000;
      total += current;
      current = 0;
      continue;
    }
    final v = _esNum[w];
    if (v == null) continue;
    current += v;
  }
  final n = total + current;
  return n == 0 ? null : n;
}

int? _indexOfAny(String lower, List<String> marks) {
  int? best;
  for (final m in marks) {
    final i = lower.indexOf(m);
    if (i < 0) continue;
    if (best == null || i < best) best = i;
  }
  return best;
}

List<DeedPerson> _uniqueNie(List<DeedPerson> people) {
  final seen = <String>{};
  return [
    for (final p in people)
      if (seen.add(p.nie)) p,
  ];
}

List<DeedPerson> _pairRespectivamente(List<DeedPerson> people, String text) {
  if (people.isEmpty) return people;
  final byNie = {for (final p in people) p.nie: p};
  for (final m in RegExp('respectivamente', caseSensitive: false).allMatches(text)) {
    final from = m.start - 900 < 0 ? 0 : m.start - 900;
    final window = text.substring(from, m.end);
    final names = [
      for (final n in _dName.allMatches(window)) _tidyName(n.group(1) ?? ''),
    ].where(looksLikeDeedPersonName).toList();
    final nies = [
      for (final n in _deedNie.allMatches(window))
        '${n.group(1)}${n.group(2)}${n.group(3)}'.toUpperCase(),
    ];
    final take = names.length < nies.length ? names.length : nies.length;
    if (take < 2) continue;
    final nameSlice = names.sublist(names.length - take);
    final nieSlice = nies.sublist(nies.length - take);
    for (var i = 0; i < take; i++) {
      final nie = nieSlice[i];
      final prev = byNie[nie];
      if (prev == null) continue;
      byNie[nie] = DeedPerson(nie: nie, name: nameSlice[i], index: prev.index);
    }
  }
  return [for (final p in people) byNie[p.nie] ?? p];
}

String? _deedNotary(String text) {
  final m = RegExp(
    r'Ante m[ií],\s+([A-ZÁÉÍÓÚÜÑ][A-ZÁÉÍÓÚÜÑ\s\.]+?),\s+Notario',
    caseSensitive: false,
  ).firstMatch(text);
  final n = _tidyName(m?.group(1) ?? '');
  return n.isEmpty ? null : n;
}

String? _deedCadastral(String text) {
  final m = RegExp(
    r'referencia\s+catastral[.\s:\-]*([0-9]{7}[A-Z]{2}[0-9]{4}[A-Z][0-9]{4}[A-Z]{2})',
    caseSensitive: false,
  ).firstMatch(text.replaceAll('\n', ' '));
  return m?.group(1)?.toUpperCase();
}

String? _deedParcela(String text) {
  final from = text.toLowerCase().indexOf('urbana');
  final slice = from < 0
      ? text
      : text.substring(from, from + 1800 > text.length ? text.length : from + 1800);
  final m = RegExp(
    r'parcela\s+([A-Z0-9][A-Z0-9.\-]{1,12})',
    caseSensitive: false,
  ).firstMatch(slice);
  return m?.group(1)?.toUpperCase();
}

String? _deedRegistry(String text) {
  final flat = text.replaceAll('\n', ' ');
  final lugar = RegExp(
    r'Registro de la Propiedad de\s+([A-ZÁÉÍÓÚÜÑa-záéíóúüñ\s]+?)(?:\s+N[úu]mero|,)',
    caseSensitive: false,
  ).firstMatch(flat);
  final finca = RegExp(
    r'finca\s+n[úu]mero\s+([\d.]+)',
    caseSensitive: false,
  ).firstMatch(flat);
  final bits = [
    if (lugar != null) _tidyName(lugar.group(1)!),
    if (finca != null) 'finca ${finca.group(1)}',
  ];
  return bits.isEmpty ? null : bits.join(', ');
}

String? _deedLawyer(String text) {
  final m = RegExp(
    r'[“"«]([^“"»]{6,80}ABOGAD[^“"»]{0,40})[”"»]',
    caseSensitive: false,
  ).firstMatch(text);
  final n = _tidyName(m?.group(1) ?? '');
  return n.isEmpty ? null : n.replaceAll(RegExp(r'\s+'), ' ');
}

String? _deedSalePrice(String text) {
  final at = text.toLowerCase().indexOf('precio de esta compraventa');
  if (at < 0) {
    final alt = text.toLowerCase().indexOf('es precio de');
    if (alt < 0) return null;
    return _firstEuro(text, alt, 500);
  }
  return _firstEuro(text, at, 500);
}

String? _deedReferenceValue(String text) {
  final at = text.toLowerCase().indexOf('valor de referencia');
  if (at < 0) return null;
  return _firstEuro(text, at, 400);
}

String? _firstEuro(String text, int at, int window) {
  final end = at + window > text.length ? text.length : at + window;
  final m = _euroParen.firstMatch(text.substring(at, end));
  if (m == null) return null;
  return m.group(1)!.replaceAll('.', '').replaceAll(',', '.');
}

String? _deedAddress(String text) {
  final from = text.toLowerCase().indexOf('urbana');
  if (from < 0) return null;
  final slice = text.substring(
    from,
    from + 2200 > text.length ? text.length : from + 2200,
  );
  final flat = slice.replaceAll('\n', ' ');
  final hoy = RegExp(
    r'hoy calle\s+([^,\n]+?),\s+n[úu]mero\s+([^\s,]+)',
    caseSensitive: false,
  ).firstMatch(flat);
  final mun = RegExp(
    r't[ée]rmino de\s+([A-ZÁÉÍÓÚÜÑa-záéíóúüñ]+)',
    caseSensitive: false,
  ).firstMatch(flat);
  if (hoy == null) return mun == null ? null : _tidyName(mun.group(1)!);
  final street = _tidyName(hoy.group(1)!);
  final num = hoy.group(2)!;
  final town = mun == null ? '' : ', ${_tidyName(mun.group(1)!)}';
  return 'calle $street, $num$town';
}

String _tidyName(String raw) {
  return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// D. jméno má aspoň dvě slova. Jedno slovo je město (Kneznou) nebo národnost.
bool looksLikeDeedPersonName(String raw) {
  final parts = raw
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.length >= 2)
      .toList();
  return parts.length >= 2;
}

String _foldEs(String raw) {
  return raw.toLowerCase().replaceAllMapped(RegExp(r'[áéíóúüñ]'), (m) {
    switch (m.group(0)) {
      case 'á':
        return 'a';
      case 'é':
        return 'e';
      case 'í':
        return 'i';
      case 'ó':
        return 'o';
      case 'ú':
      case 'ü':
        return 'u';
      case 'ñ':
        return 'n';
      default:
        return m.group(0)!;
    }
  });
}

const _esNum = <String, int>{
  'cero': 0,
  'un': 1,
  'uno': 1,
  'una': 1,
  'dos': 2,
  'tres': 3,
  'cuatro': 4,
  'cinco': 5,
  'seis': 6,
  'siete': 7,
  'ocho': 8,
  'nueve': 9,
  'diez': 10,
  'once': 11,
  'doce': 12,
  'trece': 13,
  'catorce': 14,
  'quince': 15,
  'dieciseis': 16,
  'diecisiete': 17,
  'dieciocho': 18,
  'diecinueve': 19,
  'veinte': 20,
  'veintiun': 21,
  'veintiuno': 21,
  'veintidos': 22,
  'veintitres': 23,
  'veinticuatro': 24,
  'veinticinco': 25,
  'veintiseis': 26,
  'veintisiete': 27,
  'veintiocho': 28,
  'veintinueve': 29,
  'treinta': 30,
  'cuarenta': 40,
  'cincuenta': 50,
  'sesenta': 60,
  'setenta': 70,
  'ochenta': 80,
  'noventa': 90,
  'cien': 100,
  'ciento': 100,
  'doscientos': 200,
  'trescientos': 300,
  'cuatrocientos': 400,
  'quinientos': 500,
  'seiscientos': 600,
  'setecientos': 700,
  'ochocientos': 800,
  'novecientos': 900,
};
