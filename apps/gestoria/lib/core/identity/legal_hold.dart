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
