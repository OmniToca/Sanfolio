import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/identity/legal_hold.dart';

void main() {
  test('legal hold blokuje purge do data including, včera už ne', () {
    final today = DateTime(2026, 9, 13);
    expect(
      legalHoldBlocks(until: DateTime(2026, 9, 13), today: today),
      isTrue,
    );
    expect(
      legalHoldBlocks(until: DateTime(2030, 1, 1), today: today),
      isTrue,
    );
    expect(
      legalHoldBlocks(until: DateTime(2026, 9, 12), today: today),
      isFalse,
    );
    expect(looksLikeLegalHoldError('Exception: legal_hold'), isTrue);
    expect(looksLikeLegalHoldError('not_in_trash'), isFalse);
    // anonymize_cliente používá stejné until >= dnes.
    expect(
      legalHoldBlocks(until: DateTime(2026, 9, 13), today: today),
      isTrue,
    );
  });

  test('default hold je +6 let, souborový hold nekryje jiný dokument', () {
    expect(
      defaultLegalHoldUntil(DateTime(2026, 9, 13)),
      DateTime(2032, 9, 13),
    );
    expect(legalHoldUntilIso(DateTime(2032, 9, 13)), '2032-09-13');
    expect(
      holdCoversDocumento(
        until: DateTime(2030, 1, 1),
        holdDocumentoId: null,
        documentoId: 'a',
        today: DateTime(2026, 9, 13),
      ),
      isTrue,
    );
    expect(
      holdCoversDocumento(
        until: DateTime(2030, 1, 1),
        holdDocumentoId: 'a',
        documentoId: 'b',
        today: DateTime(2026, 9, 13),
      ),
      isFalse,
    );
  });
}
