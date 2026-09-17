/// Řádky inboxových seznamů 210 a po notáři. RPC je zdroj, Dart jen čte.
class Season210Row {
  const Season210Row({
    required this.clienteId,
    required this.clienteNombre,
    required this.expedienteId,
    this.bloqueId,
    this.periodo,
    this.periodicity,
    this.dueOn,
    this.bloqueStatus,
    this.missingDocs = const [],
  });

  final String clienteId;
  final String clienteNombre;
  final String expedienteId;
  final String? bloqueId;
  final String? periodo;
  final String? periodicity;
  final String? dueOn;
  final String? bloqueStatus;
  final List<String> missingDocs;
}

class AfterNotaryRow {
  const AfterNotaryRow({
    required this.clienteId,
    required this.clienteNombre,
    required this.inmuebleId,
    required this.expedienteId,
    required this.tasks,
    this.direccion,
    this.escrituraFecha,
    this.taxExpedienteId,
  });

  final String clienteId;
  final String clienteNombre;
  final String inmuebleId;
  final String expedienteId;
  final String? direccion;
  final String? escrituraFecha;
  final String? taxExpedienteId;

  /// plusvalia / agua / luz / gaz / comunidad / modelo_210
  final List<String> tasks;
}

/// Otevřený 210 bez data podání. Archiv a hotovo sem nepatří.
bool season210Open({
  required String bloqueStatus,
  required String expedienteEstado,
  required String filed,
}) {
  if (filed.trim().isNotEmpty) return false;
  if (bloqueStatus == 'off' || bloqueStatus == 'done') return false;
  if (expedienteEstado == 'archivado' || expedienteEstado == 'hecho') {
    return false;
  }
  return true;
}

/// Po notáři zbývá práce, když běží plusvalía, díra na dodávce,
/// nebo čerstvá koupě (90 dní) bez podaného 210.
bool afterNotaryStillOpen({
  required bool plusvaliaOpen,
  required Iterable<String> supplyHoles,
  required bool recentEscritura,
  required bool tax210Needed,
}) {
  if (plusvaliaOpen) return true;
  if (supplyHoles.isNotEmpty) return true;
  return recentEscritura && tax210Needed;
}

/// IBI v kampani: kancelář má splatnost a zbývá recibo nebo termín v okně.
bool seasonIbiOpen({
  required String bloqueStatus,
  required bool dueConfigured,
  required bool inWarnWindow,
  required bool missingRecibo,
}) {
  if (!dueConfigured) return false;
  if (bloqueStatus == 'off' || bloqueStatus == 'done') return false;
  return missingRecibo || inWarnWindow;
}

String? firstSupplyTask(Iterable<String> tasks) {
  for (final k in const ['agua', 'luz', 'gaz', 'comunidad']) {
    if (tasks.contains(k)) return k;
  }
  return null;
}

String draftTemplateForNotary(Iterable<String> tasks) {
  if (firstSupplyTask(tasks) != null) return 'cambio_titular';
  if (tasks.contains('plusvalia')) return 'recordatorio';
  return 'falta_documento';
}

String draftBloqueForNotary(Iterable<String> tasks) {
  return firstSupplyTask(tasks) ??
      (tasks.contains('plusvalia') ? 'plusvalia' : 'modelo_210');
}

Season210Row? season210RowFromRpc(Map raw) {
  final clienteId = '${raw['cliente_id'] ?? ''}'.trim();
  final expedienteId = '${raw['expediente_id'] ?? ''}'.trim();
  if (clienteId.isEmpty || expedienteId.isEmpty) return null;
  final bloqueId = '${raw['bloque_id'] ?? ''}'.trim();
  return Season210Row(
    clienteId: clienteId,
    clienteNombre: '${raw['cliente_nombre'] ?? ''}'.trim(),
    expedienteId: expedienteId,
    bloqueId: bloqueId.isEmpty ? null : bloqueId,
    periodo: _opt(raw['periodo']),
    periodicity: _opt(raw['periodicity']),
    dueOn: _opt(raw['due_on']),
    bloqueStatus: _opt(raw['bloque_status']),
    missingDocs: _strList(raw['missing_docs']),
  );
}

AfterNotaryRow? afterNotaryRowFromRpc(Map raw) {
  final clienteId = '${raw['cliente_id'] ?? ''}'.trim();
  final expedienteId = '${raw['expediente_id'] ?? ''}'.trim();
  final inmuebleId = '${raw['inmueble_id'] ?? ''}'.trim();
  final tasks = _strList(raw['tasks']);
  if (clienteId.isEmpty || expedienteId.isEmpty || inmuebleId.isEmpty) {
    return null;
  }
  if (tasks.isEmpty) return null;
  final tax = '${raw['tax_expediente_id'] ?? ''}'.trim();
  return AfterNotaryRow(
    clienteId: clienteId,
    clienteNombre: '${raw['cliente_nombre'] ?? ''}'.trim(),
    inmuebleId: inmuebleId,
    expedienteId: expedienteId,
    direccion: _opt(raw['direccion']),
    escrituraFecha: _opt(raw['escritura_fecha']),
    taxExpedienteId: tax.isEmpty ? null : tax,
    tasks: tasks,
  );
}

String? _opt(Object? raw) {
  final v = '${raw ?? ''}'.trim();
  return v.isEmpty ? null : v;
}

List<String> _strList(Object? raw) {
  if (raw is List) {
    return [
      for (final x in raw)
        if ('$x'.trim().isNotEmpty) '$x'.trim(),
    ];
  }
  final s = '${raw ?? ''}'.trim();
  if (s.isEmpty) return const [];
  return [
    for (final p in s.split(','))
      if (p.trim().isNotEmpty) p.trim(),
  ];
}
