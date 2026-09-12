import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/money/cents.dart';

void main() {
  test('eura na cents — čárka i tečka', () {
    expect(parseEurosToCents('150,50'), 15050);
    expect(parseEurosToCents('150.50'), 15050);
    expect(parseEurosToCents('0'), 0);
  });

  test('zbývá = přijato − vyúčtováno', () {
    expect(centsFromStored('20000') - centsFromStored('5000'), 15000);
    expect(formatCents(15000), '150,00');
  });
}
