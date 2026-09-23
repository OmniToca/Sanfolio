import 'stoh.dart';

/// Papír, který kancelář už zařadila. Vzor pro další sken, ne trénink modelu.
class OfficePaperExample {
  const OfficePaperExample({
    required this.bloqueKey,
    this.tipo = 'other',
    this.source = 'ai',
    this.title = '',
    this.caption = '',
    this.filledKeys = const [],
    this.dist = 1,
  });

  final String bloqueKey;
  final String tipo;
  final String source;
  final String title;
  final String caption;
  final List<String> filledKeys;
  final double dist;

  bool get human => source == 'human';
}

/// Cosine; pod tím je stejný druh papíru. Nad tím je šum.
const kOfficeExampleMaxDist = 0.45;

/// Jeden lidský vzor stačí, jen když je skoro stejný sken.
const kOfficeExampleTightDist = 0.28;

final _nieInText = RegExp(
  r'\b(?:[XYZ]\s*-?\s*[0-9*]{7}\s*-?\s*[A-Z]|[0-9*]{8}[A-Z])\b',
  caseSensitive: false,
);
final _emailInText = RegExp(r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}', caseSensitive: false);
final _phoneInText = RegExp(r'\+?\d[\d \-]{7,14}\d');

/// NIE / mail / tel z jiného klienta do promptu dalšího extractu nepatří.
String redactOfficeExampleText(String raw) {
  var t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  t = t.replaceAll(_nieInText, '[NIE]');
  t = t.replaceAll(_emailInText, '[email]');
  t = t.replaceAll(_phoneInText, '[tel]');
  if (t.length > 120) t = t.substring(0, 120);
  return t;
}

/// Dva stejné album, nebo jeden hodně blízký lidský. Jinak hromada.
StohProposal? officeClassifyConsensus(Iterable<OfficePaperExample> raw) {
  final close = [
    for (final e in raw)
      if (e.dist <= kOfficeExampleMaxDist &&
          kStohBloqueKeys.contains(e.bloqueKey))
        e,
  ];
  if (close.isEmpty) return null;

  final byBloque = <String, List<OfficePaperExample>>{};
  for (final e in close) {
    byBloque.putIfAbsent(e.bloqueKey, () => []).add(e);
  }
  var bestKey = '';
  var bestCount = 0;
  var bestDist = 99.0;
  for (final e in byBloque.entries) {
    final n = e.value.length;
    final avg = e.value.fold<double>(0, (s, x) => s + x.dist) / n;
    if (n > bestCount || (n == bestCount && avg < bestDist)) {
      bestKey = e.key;
      bestCount = n;
      bestDist = avg;
    }
  }
  List<OfficePaperExample> winners;
  if (bestCount >= 2) {
    winners = byBloque[bestKey]!;
  } else {
    final only = close.single;
    if (!only.human || only.dist > kOfficeExampleTightDist) return null;
    winners = [only];
    bestKey = only.bloqueKey;
  }

  final tipos = <String, int>{};
  for (final e in winners) {
    final t = e.tipo.trim();
    if (t.isEmpty || t == 'other') continue;
    tipos[t] = (tipos[t] ?? 0) + 1;
  }
  var tipo = 'other';
  var tipoN = 0;
  for (final e in tipos.entries) {
    if (e.value > tipoN) {
      tipo = e.key;
      tipoN = e.value;
    }
  }
  final allowed = tiposForStohBloque(bestKey);
  if (!allowed.contains(tipo)) tipo = allowed.first;
  return StohProposal(bloqueKey: bestKey, tipo: tipo);
}

/// Krátký vzor pro LLM. Hodnoty jiných klientů ne.
String officeExamplesPrompt(Iterable<OfficePaperExample> raw) {
  final lines = <String>[];
  var i = 0;
  for (final e in raw) {
    if (e.dist > kOfficeExampleMaxDist || !kStohBloqueKeys.contains(e.bloqueKey)) {
      continue;
    }
    i += 1;
    if (i > 5) break;
    final keys = e.filledKeys.where((k) => k.startsWith('fields.')).take(8).join(',');
    final title = redactOfficeExampleText(e.title);
    final caption = redactOfficeExampleText(e.caption);
    lines.add(
      '$i. album=${e.bloqueKey} tipo=${e.tipo} source=${e.source}'
      '${keys.isEmpty ? '' : ' keys=$keys'}'
      '${title.isEmpty ? '' : ' title=$title'}'
      '${caption.isEmpty ? '' : ' caption=$caption'}',
    );
  }
  if (lines.isEmpty) return '';
  return 'This office already filed similar papers (same tenant, not this file). '
      'Follow their album and which fields they kept. Do not copy names or NIE. '
      'If they agree, proposedBloque/proposedTipo should match. '
      'IBI period is the year; address is the finca, never the SUMA office.\n'
      '${lines.join('\n')}';
}
