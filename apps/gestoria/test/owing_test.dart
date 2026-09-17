import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/money/provision.dart';
import 'package:gestoria_os/features/provision/owing.dart';

void main() {
  test('dluží jen když zbývá nula nebo míň a jsou pohyby', () {
    expect(provisionOwesOffice(receivedCents: 0, invoicedCents: 0), isFalse);
    expect(
      provisionOwesOffice(receivedCents: 100000, invoicedCents: 40000),
      isFalse,
    );
    expect(
      provisionOwesOffice(receivedCents: 100000, invoicedCents: 100000),
      isTrue,
    );
    expect(
      provisionOwesOffice(receivedCents: 50000, invoicedCents: 80000),
      isTrue,
    );
    expect(provisionOwesOffice(receivedCents: 0, invoicedCents: 1089), isTrue);
  });

  test('RPC bez pohybů nebo s přebytkem sem nepatří', () {
    expect(
      owingRowFromRpc({
        'cliente_id': 'c1',
        'received_cents': 0,
        'invoiced_cents': 0,
        'remaining_cents': 0,
      }),
      isNull,
    );
    expect(
      owingRowFromRpc({
        'cliente_id': 'c1',
        'received_cents': 100,
        'invoiced_cents': 40,
        'remaining_cents': 60,
      }),
      isNull,
    );
  });

  test('řádek dlužné zálohy čte cents a kanál, neodesílá', () {
    final row = owingRowFromRpc({
      'cliente_id': 'c1',
      'cliente_nombre': 'Ana',
      'expediente_id': 'e1',
      'bloque_id': 'b1',
      'received_cents': 50000,
      'invoiced_cents': 80000,
      'remaining_cents': -30000,
      'has_email': true,
      'has_tel': false,
    });
    expect(row?.remainingCents, -30000);
    expect(row?.hasTel, isFalse);
    expect(row?.expedienteId, 'e1');
  });
}
