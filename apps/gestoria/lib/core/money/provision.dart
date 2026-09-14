/// Pohyb zálohy. Zbývá = přijato − vyúčtováno. Žádné DPH.
class ProvisionMovement {
  const ProvisionMovement({
    required this.id,
    required this.kind,
    required this.amountCents,
    this.note,
    this.facturaId,
  });

  final String id;
  final String kind;
  final int amountCents;
  final String? note;
  final String? facturaId;
}

const provisionKinds = <String>['ingreso', 'factura', 'ajuste'];

int provisionReceivedCents(Iterable<ProvisionMovement> rows) {
  var n = 0;
  for (final r in rows) {
    if (r.kind == 'ingreso' || r.kind == 'ajuste') n += r.amountCents;
  }
  return n;
}

int provisionInvoicedCents(Iterable<ProvisionMovement> rows) {
  var n = 0;
  for (final r in rows) {
    if (r.kind == 'factura') n += r.amountCents;
  }
  return n;
}

int provisionRemainingCents(Iterable<ProvisionMovement> rows) {
  return provisionReceivedCents(rows) - provisionInvoicedCents(rows);
}
