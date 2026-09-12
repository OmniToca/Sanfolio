import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/money/provision.dart';

void main() {
  test('zbývá = ingreso + ajuste − factura, v centech', () {
    const rows = [
      ProvisionMovement(id: '1', kind: 'ingreso', amountCents: 100000),
      ProvisionMovement(id: '2', kind: 'factura', amountCents: 40000),
      ProvisionMovement(id: '3', kind: 'ajuste', amountCents: -5000),
    ];
    expect(provisionReceivedCents(rows), 95000);
    expect(provisionInvoicedCents(rows), 40000);
    expect(provisionRemainingCents(rows), 55000);
  });
}
