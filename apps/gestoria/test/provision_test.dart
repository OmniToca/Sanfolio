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
    expect(
      provisionOwesOffice(receivedCents: 95000, invoicedCents: 40000),
      isFalse,
    );
  });

  test('pohyb z knihy má facturaId, součet se nemění', () {
    const rows = [
      ProvisionMovement(
        id: '1',
        kind: 'factura',
        amountCents: 1089,
        facturaId: 'f-1',
        note: 'A-3',
      ),
    ];
    expect(provisionInvoicedCents(rows), 1089);
    expect(rows.first.facturaId, 'f-1');
  });
}
