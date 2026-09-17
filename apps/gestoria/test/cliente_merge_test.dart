import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/clientes/cliente_merge.dart';

void main() {
  test('dvě různá živá NIE nejsou duplicita i při stejném e-mailu', () {
    expect(
      canSuggestDuplicate(
        keepNie: 'Y1234567Z',
        dropNie: 'X1111111A',
        emailMatch: true,
        telMatch: true,
        nameMatch: true,
      ),
      isFalse,
    );
  });

  test('e-mail a telefon spárují, jméno jen bez NIE', () {
    expect(
      canSuggestDuplicate(
        keepNie: 'Y1234567Z',
        dropNie: 'Y1234567Z',
        emailMatch: true,
        telMatch: false,
        nameMatch: false,
      ),
      isTrue,
    );
    expect(
      canSuggestDuplicate(
        keepNie: 'Y1234567Z',
        dropNie: null,
        emailMatch: false,
        telMatch: false,
        nameMatch: true,
      ),
      isTrue,
    );
    expect(
      canSuggestDuplicate(
        keepNie: 'Y1234567Z',
        dropNie: 'Y1234567Z',
        emailMatch: false,
        telMatch: false,
        nameMatch: true,
      ),
      isFalse,
    );
  });

  test('necháme kartu s NIE, jinak starší', () {
    final older = DateTime.utc(2026, 1, 1);
    final newer = DateTime.utc(2026, 9, 1);
    expect(
      preferKeepSide(
        keepHasNie: true,
        dropHasNie: false,
        keepCreated: newer,
        dropCreated: older,
      ),
      isTrue,
    );
    expect(
      preferKeepSide(
        keepHasNie: false,
        dropHasNie: true,
        keepCreated: older,
        dropCreated: newer,
      ),
      isFalse,
    );
    expect(
      preferKeepSide(
        keepHasNie: false,
        dropHasNie: false,
        keepCreated: older,
        dropCreated: newer,
      ),
      isTrue,
    );
  });

  test('RPC pár bere jen email/tel/name', () {
    final row = duplicatePairFromRpc({
      'keep_id': 'a',
      'keep_nombre': 'Ana',
      'drop_id': 'b',
      'drop_nombre': 'Anna',
      'reason': 'email',
      'score': 90,
    });
    expect(row?.score, 90);
    expect(
      duplicatePairFromRpc({
        'keep_id': 'a',
        'drop_id': 'a',
        'reason': 'email',
      }),
      isNull,
    );
    expect(
      duplicatePairFromRpc({
        'keep_id': 'a',
        'drop_id': 'b',
        'reason': 'iban',
      }),
      isNull,
    );
  });
}
