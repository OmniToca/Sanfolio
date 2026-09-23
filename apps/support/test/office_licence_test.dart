import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_support/features/tenants/office_licence.dart';

void main() {
  test('Carpeta + AI je balíček plus doplněk', () {
    final quote = resolveLicenceQuote(
      planKey: LicencePlanKeys.carpeta,
      liveKeys: {'ai_copilot'},
      plans: const [
        LicencePlanInfo(
          key: LicencePlanKeys.carpeta,
          cents: 3900,
          includedKeys: {'carpeta_inmueble', 'messaging'},
        ),
      ],
      catalog: const [
        ModulePrice(key: 'ai_copilot', cents: 1900, alwaysOn: false),
        ModulePrice(key: 'facturacion', cents: 2900, alwaysOn: false),
      ],
    );
    expect(quote.subtotalCents, 5800);
    expect(quote.addOns.where((l) => l.on).map((l) => l.key), ['ai_copilot']);
  });
}
