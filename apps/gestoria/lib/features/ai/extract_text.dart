/// Návrh polí z textu. Nic se nezapisuje do DB — tohle není save.
class ExtractedFields {
  const ExtractedFields({
    this.nie,
    this.email,
    this.tel,
    this.nombre,
    this.iban,
  });

  final String? nie;
  final String? email;
  final String? tel;
  final String? nombre;
  final String? iban;

  bool get isEmpty =>
      (nie == null || nie!.isEmpty) &&
      (email == null || email!.isEmpty) &&
      (tel == null || tel!.isEmpty) &&
      (nombre == null || nombre!.isEmpty) &&
      (iban == null || iban!.isEmpty);

  Map<String, String> get snapshotFields => {
    if (nie != null && nie!.isNotEmpty) 'fields.nie': nie!,
    if (email != null && email!.isNotEmpty) 'fields.email': email!,
    if (tel != null && tel!.isNotEmpty) 'fields.tel': tel!,
    if (nombre != null && nombre!.isNotEmpty) 'fields.nombre': nombre!,
    if (iban != null && iban!.isNotEmpty) 'fields.iban': iban!,
  };
}

/// Řádek žlutého diffu: teď vs. návrh. Guardar je až klik člověka.
class PrefillDiff {
  const PrefillDiff({
    required this.fieldKey,
    required this.current,
    required this.proposed,
  });

  final String fieldKey;
  final String current;
  final String proposed;

  bool get changed => current.trim() != proposed.trim();
}

List<PrefillDiff> prefillDiffs({
  required Map<String, String> current,
  required Map<String, String> proposed,
}) {
  final clean = sanitizeExtractedFields(proposed);
  final keys = clean.keys.where((k) => clean[k]!.trim().isNotEmpty);
  return [
    for (final key in keys)
      PrefillDiff(
        fieldKey: key,
        current: (current[key] ?? '').trim(),
        proposed: clean[key]!.trim(),
      ),
  ];
}

Map<String, String> stringFieldMap(Object? raw) {
  if (raw is! Map) return {};
  final out = <String, String>{};
  for (final e in raw.entries) {
    final v = '${e.value}'.trim();
    if (v.isEmpty || v == 'null') continue;
    out['${e.key}'] = v;
  }
  return sanitizeExtractedFields(out);
}

/// NIE/DNI má pevnou délku. `XU` z PDF binárky není identifikátor.
bool looksLikeNie(String raw) {
  final v = raw.toUpperCase().replaceAll(RegExp(r'[\s\-\./]'), '');
  return RegExp(r'^[XYZ][0-9*]{7}[A-Z]$').hasMatch(v) ||
      RegExp(r'^[0-9*]{8}[A-Z]$').hasMatch(v);
}

/// Telefon je číslo k volání, ne kód. Proud číslic z IBAN/CUPS sem nepatří.
/// ES 9 číslic (6–9…), 34+9, nebo číslo s +. 13 číslic bez + není tel.
bool looksLikeTel(String raw) {
  if (looksLikeIban(raw)) return false;
  final hasPlus = raw.trim().startsWith('+');
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return false;
  final zeros = digits.split('').where((c) => c == '0').length;
  if (zeros > digits.length ~/ 2) return false;
  if (hasPlus) return digits.length >= 10 && digits.length <= 15;
  if (digits.length == 9 && RegExp(r'^[6789]').hasMatch(digits)) return true;
  if (digits.length == 11 &&
      digits.startsWith('34') &&
      RegExp(r'^[6789]').hasMatch(digits.substring(2))) {
    return true;
  }
  if (digits.length == 12 && digits.startsWith('420')) return true;
  return false;
}

/// ES IBAN má 24 znaků. CUPS (ES + 16 číslic + 2 písmena) sem nepatří.
bool looksLikeIban(String raw) {
  final v = compactIban(raw);
  if (!RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$').hasMatch(v)) return false;
  if (v.startsWith('ES')) return v.length == 24;
  return v.length >= 15 && v.length <= 34;
}

String compactIban(String raw) =>
    raw.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');

/// ES96 2100 9143 9413 0049 8086. Ne polykat BIC na dalším řádku.
final _iban = RegExp(
  r'\bES\s*\d{2}(?:[\s\-]?\d{4}){5}\b|\b[A-Z]{2}\d{2}[A-Z0-9]{10,30}\b',
);

final _ibanCompactEs = RegExp(r'ES\d{22}');

String formatIban(String raw) {
  final v = compactIban(raw);
  if (v.length < 15) return raw.trim();
  final buf = StringBuffer();
  for (var i = 0; i < v.length; i++) {
    if (i > 0 && i % 4 == 0) buf.write(' ');
    buf.write(v[i]);
  }
  return buf.toString();
}

String shownFieldValue(String key, String value) {
  if (key == 'fields.iban') return formatIban(value);
  return value;
}

String? firstIbanIn(String text) {
  for (final m in _iban.allMatches(text)) {
    final raw = m.group(0);
    if (raw != null && looksLikeIban(raw)) return compactIban(raw);
  }
  final compact = compactIban(text);
  final es = _ibanCompactEs.firstMatch(compact)?.group(0);
  if (es != null && looksLikeIban(es)) return es;
  return null;
}

String stripIbans(String text) {
  return text.replaceAllMapped(_iban, (m) {
    final raw = m.group(0) ?? '';
    return looksLikeIban(raw) ? ' ' : raw;
  });
}

/// ISO kód v přepisu doplní pole. Ne čtení jednoho názvu souboru.
Map<String, String> overlayIbanFromBody(
  Map<String, String> fields, {
  String? bodyText,
}) {
  final body = (bodyText ?? fields['body_text'] ?? '').trim();
  final next = Map<String, String>.from(fields);
  if (body.isNotEmpty) {
    final iban = firstIbanIn(body);
    if (iban != null && (next['fields.iban'] ?? '').trim().isEmpty) {
      next['fields.iban'] = iban;
    }
  }
  return sanitizeExtractedFields(next);
}

const kIdentifierFieldKeys = <String>{
  'fields.iban',
  'fields.cups',
  'fields.nie',
  'fields.sellerNie',
  'fields.sumaId',
  'fields.cadastral',
  'fields.contractNo',
  'fields.docNumber',
  'fields.protocol',
  'fields.invoiceNo',
};

/// Stejné číslice v IBAN/CUPS/NIE nejsou telefon — u každého klienta.
bool telTakenFromIdentifiers(Map<String, String> fields) {
  final tel = (fields['fields.tel'] ?? '').replaceAll(RegExp(r'[^\d]'), '');
  if (tel.length < 8) return false;
  for (final key in kIdentifierFieldKeys) {
    final id = (fields[key] ?? '')
        .toUpperCase()
        .replaceAll(RegExp(r'[\s\-]'), '');
    if (id.contains(tel)) return true;
  }
  return false;
}

String compactTel(String raw) {
  final hasPlus = raw.trim().startsWith('+');
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  return hasPlus ? '+$digits' : digits;
}

const kExtractStatus = 'extract_status';
const kProposedBloqueKey = 'proposed_bloque_key';
const kProposedTipo = 'proposed_tipo';

bool isExtractPending(Map<String, String> fields) =>
    (fields[kExtractStatus] ?? '') == 'pending';

bool isExtractFailed(Map<String, String> fields) =>
    (fields[kExtractStatus] ?? '') == 'failed';

const kLongExtractKeys = {
  'fields.buyers',
  'fields.sellers',
  'fields.address',
  'fields.registry',
  'fields.lawyer',
  'fields.attorney',
  'fields.notes',
};

/// Zahodí odpad z OCR/PDF, ať se nenabízí k uložení přes platný NIE.
Map<String, String> sanitizeExtractedFields(Map<String, String> raw) {
  final out = <String, String>{};
  for (final e in raw.entries) {
    final v = e.value.trim();
    if (v.isEmpty) continue;
    switch (e.key) {
      case kExtractStatus:
        if (v == 'pending' || v == 'failed') out[e.key] = v;
      case 'fields.nie':
      case 'fields.sellerNie':
        if (looksLikeNie(v)) out[e.key] = v.toUpperCase().replaceAll(' ', '');
      case 'fields.tel':
        if (looksLikeTel(v)) out[e.key] = compactTel(v);
      case 'fields.iban':
        if (looksLikeIban(v)) out[e.key] = compactIban(v);
      case 'fields.email':
        if (v.contains('@') && v.length <= 120) out[e.key] = v.toLowerCase();
      case 'body_text':
        out[e.key] = v.length > 100000 ? v.substring(0, 100000) : v;
      default:
        final max = kLongExtractKeys.contains(e.key) ? 2000 : 200;
        if (v.length <= max) out[e.key] = v;
    }
  }
  if (telTakenFromIdentifiers(out)) {
    out.remove('fields.tel');
  }
  return out;
}

/// Pole desky vs. plný text PDF. Guardar zapisuje zvlášť.
class DocumentoTranscript {
  const DocumentoTranscript({this.fields = const {}, this.bodyText});

  final Map<String, String> fields;
  final String? bodyText;
}

DocumentoTranscript splitDocumentoTranscript(Map<String, String> raw) {
  var fields = Map<String, String>.from(sanitizeExtractedFields(raw));
  fields.remove(kExtractStatus);
  fields.remove(kProposedBloqueKey);
  fields.remove(kProposedTipo);
  final body = fields.remove('body_text')?.trim();
  if (body != null && body.isNotEmpty) {
    fields = overlayIbanFromBody(fields, bodyText: body);
  }
  return DocumentoTranscript(
    fields: fields,
    bodyText: body == null || body.isEmpty ? null : body,
  );
}

/// Řádek `documentos`: pole + přepis + jestli je blob vysypaný.
DocumentoTranscript transcriptFromDocumentoRow(Map raw) {
  final extracted = stringFieldMap(raw['extracted']);
  final col = '${raw['body_text'] ?? ''}'.trim();
  return splitDocumentoTranscript({
    ...extracted,
    if (col.isNotEmpty) 'body_text': col,
  });
}

/// Surový OCR je pro asistenta. Na papír na stole jen když ještě nejsou pole.
bool showDocumentoBodyOnPaper({
  required bool hasShownFields,
  required String? bodyText,
}) {
  if ((bodyText ?? '').trim().isEmpty) return false;
  return !hasShownFields;
}

/// Fulltext RPC odmítne kratší než 3 znaky (stejně jako SQL).
bool documentTextSearchQueryOk(String q) => q.trim().length >= 3;

bool storagePurgedFromRow(Map raw) => raw['storage_purged_at'] != null;

final _nie = RegExp(
  r'\b(?:[XYZ][0-9*]{7}[A-Z]|[0-9*]{8}[A-Z])\b',
  caseSensitive: false,
);
final _email = RegExp(
  r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
  caseSensitive: false,
);
final _telLabeled = RegExp(
  r'(?:tel[eé]fono|m[oó]vil|\btel\b|phone)[:\s]*(\+?\d[\d \-]{7,14}\d)',
  caseSensitive: false,
);
final _telPlus = RegExp(r'\+\d{9,14}');

ExtractedFields extractFromText(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const ExtractedFields();
  final iban = firstIbanIn(text);
  final withoutIban = stripIbans(text);
  final nieMatch = _nie.firstMatch(text)?.group(0)?.toUpperCase();
  final email = _email.firstMatch(text)?.group(0)?.toLowerCase();
  final telRaw = _telLabeled.firstMatch(withoutIban)?.group(1) ??
      _telPlus.firstMatch(withoutIban)?.group(0);
  final tel = telRaw == null ? null : compactTel(telRaw);
  return ExtractedFields(
    nie: nieMatch != null && looksLikeNie(nieMatch) ? nieMatch : null,
    email: email,
    tel: tel != null && looksLikeTel(tel) ? tel : null,
    iban: iban,
  );
}
