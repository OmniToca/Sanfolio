/// Hold je `until` jako `date` v Europe/Madrid. Dnes >= until ještě drží (včetně).
bool legalHoldBlocks({
  required DateTime until,
  required DateTime today,
}) {
  final u = DateTime(until.year, until.month, until.day);
  final t = DateTime(today.year, today.month, today.day);
  return !u.isBefore(t);
}

bool looksLikeLegalHoldError(Object error) {
  return '$error'.toLowerCase().contains('legal_hold');
}

/// Daň/obchod 4–6 let. Default na horní mez, owner datum opraví.
DateTime defaultLegalHoldUntil(DateTime today) {
  return DateTime(today.year + 6, today.month, today.day);
}

String legalHoldUntilIso(DateTime until) {
  final d = DateTime(until.year, until.month, until.day);
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

DateTime? parseLegalHoldUntil(Object? raw) {
  final s = '$raw'.trim();
  if (s.isEmpty || s == 'null') return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (m == null) return null;
  return DateTime(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
  );
}

/// Klientský hold kryje všechny papíry. Řádek na dokumentu jen ten soubor.
bool holdCoversDocumento({
  required DateTime until,
  String? holdDocumentoId,
  required String documentoId,
  required DateTime today,
}) {
  if (!legalHoldBlocks(until: until, today: today)) return false;
  if (holdDocumentoId == null || holdDocumentoId.isEmpty) return true;
  return holdDocumentoId == documentoId;
}
