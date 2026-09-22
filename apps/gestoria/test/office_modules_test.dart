import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/modules/module_catalog.dart';
import 'package:gestoria_os/core/modules/office_licence.dart';

void main() {
  test('placené služby jsou v katalogu, jádro a portál ne', () {
    final keys = [for (final m in officeToggleModules) m.key];
    expect(keys, containsAll(['messaging', 'facturacion', 'ai_copilot']));
    expect(keys, isNot(contains('core')));
    expect(keys, isNot(contains('client_portal')));
  });

  test('měsíční poplatek je součet ceníku minus sleva kanceláře', () {
    const quote = LicenceQuote(
      discountBps: 2000,
      lines: [
        LicenceLine(key: 'core', cents: 4900, on: true, alwaysOn: true),
        LicenceLine(key: 'messaging', cents: 1900, on: true),
        LicenceLine(key: 'facturacion', cents: 2900, on: false),
      ],
    );
    expect(quote.subtotalCents, 6800);
    expect(quote.discountCents, 1360);
    expect(quote.totalCents, 5440);
    expect(quote.discountPercent, 20);
  });

  test('sleva 100 % je měsíc zdarma', () {
    const quote = LicenceQuote(
      discountBps: 10000,
      lines: [
        LicenceLine(key: 'core', cents: 4900, on: true, alwaysOn: true),
      ],
    );
    expect(quote.totalCents, 0);
  });
}
