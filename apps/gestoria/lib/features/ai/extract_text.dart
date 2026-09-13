/// Návrh polí z textu. Nic se nezapisuje do DB — tohle není save.
class ExtractedFields {
  const ExtractedFields({this.nie, this.email, this.tel, this.nombre});

  final String? nie;
  final String? email;
  final String? tel;
  final String? nombre;

  bool get isEmpty =>
      (nie == null || nie!.isEmpty) &&
      (email == null || email!.isEmpty) &&
      (tel == null || tel!.isEmpty) &&
      (nombre == null || nombre!.isEmpty);

  Map<String, String> get snapshotFields => {
    if (nie != null && nie!.isNotEmpty) 'fields.nie': nie!,
    if (email != null && email!.isNotEmpty) 'fields.email': email!,
    if (tel != null && tel!.isNotEmpty) 'fields.tel': tel!,
    if (nombre != null && nombre!.isNotEmpty) 'fields.nombre': nombre!,
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

/// Telefon 9–15 číslic. Proud nul z PDF není tel.
bool looksLikeTel(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.length < 9 || digits.length > 15) return false;
  final zeros = digits.split('').where((c) => c == '0').length;
  return zeros <= digits.length ~/ 2;
}

String compactTel(String raw) {
  final hasPlus = raw.trim().startsWith('+');
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  return hasPlus ? '+$digits' : digits;
}

const kExtractStatus = 'extract_status';

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
      case 'fields.email':
        if (v.contains('@') && v.length <= 120) out[e.key] = v.toLowerCase();
      case 'body_text':
        out[e.key] = v.length > 100000 ? v.substring(0, 100000) : v;
      default:
        final max = kLongExtractKeys.contains(e.key) ? 2000 : 200;
        if (v.length <= max) out[e.key] = v;
    }
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
  final fields = Map<String, String>.from(sanitizeExtractedFields(raw));
  fields.remove(kExtractStatus);
  final body = fields.remove('body_text')?.trim();
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
final _tel = RegExp(r'\+?\d[\d \-]{7,14}\d');

ExtractedFields extractFromText(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const ExtractedFields();
  final nieMatch = _nie.firstMatch(text)?.group(0)?.toUpperCase();
  final email = _email.firstMatch(text)?.group(0)?.toLowerCase();
  final telRaw = _tel.firstMatch(text)?.group(0);
  final tel = telRaw == null ? null : compactTel(telRaw);
  return ExtractedFields(
    nie: nieMatch != null && looksLikeNie(nieMatch) ? nieMatch : null,
    email: email,
    tel: tel != null && looksLikeTel(tel) ? tel : null,
  );
}
