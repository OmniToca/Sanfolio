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
  final keys = proposed.keys.where((k) => proposed[k]!.trim().isNotEmpty);
  return [
    for (final key in keys)
      PrefillDiff(
        fieldKey: key,
        current: (current[key] ?? '').trim(),
        proposed: proposed[key]!.trim(),
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
  return out;
}

final _nie = RegExp(
  r'\b[XYZ]\d{0,3}\*{0,4}\d{0,4}[A-Z]\b',
  caseSensitive: false,
);
final _email = RegExp(r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}', caseSensitive: false);
final _tel = RegExp(r'\+?\d[\d \-]{7,}\d');

ExtractedFields extractFromText(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const ExtractedFields();
  final nie = _nie.firstMatch(text)?.group(0)?.toUpperCase();
  final email = _email.firstMatch(text)?.group(0)?.toLowerCase();
  final tel = _tel.firstMatch(text)?.group(0)?.replaceAll(RegExp(r'[^\d+]'), '');
  return ExtractedFields(
    nie: nie,
    email: email,
    tel: (tel != null && tel.length >= 8) ? tel : null,
  );
}
