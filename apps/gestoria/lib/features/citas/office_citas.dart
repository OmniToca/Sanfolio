/// City dne: plazos `cita_*` + notář z `escritura_fecha`. Ne nová ikona v railu.
class OfficeCitaRow {
  const OfficeCitaRow({
    required this.clienteId,
    required this.clienteNombre,
    required this.bloqueKey,
    required this.kind,
    required this.dueOn,
    this.expedienteId,
    this.bloqueId,
    this.hasEmail = true,
    this.hasTel = true,
    this.lastRequestedAt,
  });

  final String clienteId;
  final String clienteNombre;
  final String bloqueKey;
  final String kind;
  final String dueOn;
  final String? expedienteId;
  final String? bloqueId;
  final bool hasEmail;
  final bool hasTel;
  final DateTime? lastRequestedAt;
}

const officeCitaKinds = <String>{
  'nie',
  'policia',
  'ayuntamiento',
  'testament',
  'escritura',
};

/// Španělský papír ve výzvě. Staff i18n sem nepatří.
String citaBloqueLabel(String kind) {
  return switch (kind) {
    'nie' => 'NIE',
    'policia' => 'Policía',
    'ayuntamiento' => 'Ayuntamiento',
    'testament' => 'Testamento',
    'escritura' => 'Escritura',
    _ => kind,
  };
}

String citaKindOf({required String plazoKind, required String bloqueKey}) {
  if (bloqueKey == 'escritura' || plazoKind == 'escritura') return 'escritura';
  if (bloqueKey == 'nie_tramite' || plazoKind == 'cita_nie') return 'nie';
  if (bloqueKey == 'policia') return 'policia';
  if (bloqueKey == 'ayuntamiento') return 'ayuntamiento';
  if (bloqueKey == 'testament') return 'testament';
  return bloqueKey;
}

String officeDayIso(DateTime day) {
  return '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

DateTime officeDayToday([DateTime? now]) {
  final n = now ?? DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

OfficeCitaRow? officeCitaRowFromRpc(Map raw) {
  final clienteId = '${raw['cliente_id'] ?? ''}'.trim();
  if (clienteId.isEmpty) return null;
  final bloqueKey = '${raw['bloque_key'] ?? ''}'.trim();
  final plazoKind = '${raw['plazo_kind'] ?? ''}'.trim();
  final kind = citaKindOf(plazoKind: plazoKind, bloqueKey: bloqueKey);
  if (!officeCitaKinds.contains(kind)) return null;
  final due = '${raw['due_on'] ?? ''}'.trim();
  if (due.isEmpty) return null;
  final expedienteId = '${raw['expediente_id'] ?? ''}'.trim();
  final bloqueId = '${raw['bloque_id'] ?? ''}'.trim();
  return OfficeCitaRow(
    clienteId: clienteId,
    clienteNombre: '${raw['cliente_nombre'] ?? ''}'.trim(),
    bloqueKey: bloqueKey.isEmpty ? kind : bloqueKey,
    kind: kind,
    dueOn: due.length >= 10 ? due.substring(0, 10) : due,
    expedienteId: expedienteId.isEmpty ? null : expedienteId,
    bloqueId: bloqueId.isEmpty ? null : bloqueId,
    hasEmail: raw['has_email'] != false,
    hasTel: raw['has_tel'] != false,
    lastRequestedAt: DateTime.tryParse('${raw['last_requested_at'] ?? ''}'),
  );
}
