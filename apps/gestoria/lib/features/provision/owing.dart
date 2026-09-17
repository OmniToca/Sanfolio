import '../../core/money/provision.dart';

/// Řádek office-wide: záloha zbývá nula nebo míň. Prázdná složka sem nepatří.
class OwingRow {
  const OwingRow({
    required this.clienteId,
    required this.clienteNombre,
    required this.receivedCents,
    required this.invoicedCents,
    required this.remainingCents,
    this.expedienteId,
    this.bloqueId,
    this.hasEmail = true,
    this.hasTel = true,
    this.lastRequestedAt,
  });

  final String clienteId;
  final String clienteNombre;
  final String? expedienteId;
  final String? bloqueId;
  final int receivedCents;
  final int invoicedCents;
  final int remainingCents;
  final bool hasEmail;
  final bool hasTel;
  final DateTime? lastRequestedAt;
}

int _cents(Object? v) {
  if (v is int) return v;
  return int.tryParse('$v') ?? 0;
}

OwingRow? owingRowFromRpc(Map raw) {
  final clienteId = '${raw['cliente_id'] ?? ''}'.trim();
  if (clienteId.isEmpty) return null;
  final received = _cents(raw['received_cents']);
  final invoiced = _cents(raw['invoiced_cents']);
  final remaining = raw.containsKey('remaining_cents')
      ? _cents(raw['remaining_cents'])
      : received - invoiced;
  if (!provisionOwesOffice(receivedCents: received, invoicedCents: invoiced)) {
    return null;
  }
  final expedienteId = '${raw['expediente_id'] ?? ''}'.trim();
  final bloqueId = '${raw['bloque_id'] ?? ''}'.trim();
  return OwingRow(
    clienteId: clienteId,
    clienteNombre: '${raw['cliente_nombre'] ?? ''}'.trim(),
    expedienteId: expedienteId.isEmpty ? null : expedienteId,
    bloqueId: bloqueId.isEmpty ? null : bloqueId,
    receivedCents: received,
    invoicedCents: invoiced,
    remainingCents: remaining,
    hasEmail: raw['has_email'] != false,
    hasTel: raw['has_tel'] != false,
    lastRequestedAt: DateTime.tryParse('${raw['last_requested_at'] ?? ''}'),
  );
}
