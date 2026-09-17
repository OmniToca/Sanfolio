/// Návrh sloučení po CSV. Dvě karty s různým živým NIE nejsou duplicita.
class DuplicatePair {
  const DuplicatePair({
    required this.keepId,
    required this.keepNombre,
    required this.dropId,
    required this.dropNombre,
    required this.reason,
    required this.score,
  });

  final String keepId;
  final String keepNombre;
  final String dropId;
  final String dropNombre;
  final String reason;
  final int score;
}

/// E-mail a telefon spáruje vždy. Jméno jen když aspoň jedna karta nemá NIE.
bool canSuggestDuplicate({
  required String? keepNie,
  required String? dropNie,
  required bool emailMatch,
  required bool telMatch,
  required bool nameMatch,
}) {
  final k = (keepNie ?? '').trim();
  final d = (dropNie ?? '').trim();
  if (k.isNotEmpty && d.isNotEmpty && k != d) return false;
  if (emailMatch || telMatch) return true;
  if (nameMatch && (k.isEmpty || d.isEmpty)) return true;
  return false;
}

/// Necháme kartu s NIE, jinak starší.
bool preferKeepSide({
  required bool keepHasNie,
  required bool dropHasNie,
  required DateTime keepCreated,
  required DateTime dropCreated,
}) {
  if (keepHasNie != dropHasNie) return keepHasNie;
  return !keepCreated.isAfter(dropCreated);
}

DuplicatePair? duplicatePairFromRpc(Map raw) {
  final keepId = '${raw['keep_id'] ?? ''}'.trim();
  final dropId = '${raw['drop_id'] ?? ''}'.trim();
  if (keepId.isEmpty || dropId.isEmpty || keepId == dropId) return null;
  final reason = '${raw['reason'] ?? ''}'.trim();
  if (reason != 'email' && reason != 'tel' && reason != 'name') return null;
  final scoreRaw = raw['score'];
  final score = scoreRaw is int ? scoreRaw : int.tryParse('$scoreRaw') ?? 0;
  return DuplicatePair(
    keepId: keepId,
    keepNombre: '${raw['keep_nombre'] ?? ''}'.trim(),
    dropId: dropId,
    dropNombre: '${raw['drop_nombre'] ?? ''}'.trim(),
    reason: reason,
    score: score,
  );
}
