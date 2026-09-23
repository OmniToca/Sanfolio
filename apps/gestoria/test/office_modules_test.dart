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

  test('měsíční poplatek je cena balíčku plus doplněk minus sleva', () {
    final quote = resolveLicenceQuote(
      discountBps: 2000,
      planKey: LicencePlanKeys.carpeta,
      liveKeys: {'carpeta_inmueble', 'messaging', 'ai_copilot'},
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
    expect(quote.planKey, LicencePlanKeys.carpeta);
    expect(quote.addOns.where((l) => l.on).map((l) => l.key), ['ai_copilot']);
    expect(quote.subtotalCents, 5800);
    expect(quote.discountCents, 1160);
    expect(quote.totalCents, 4640);
    expect(quote.discountPercent, 20);
  });

  test('Asesoría neúčtuje AI ani faktury zvlášť', () {
    final quote = resolveLicenceQuote(
      planKey: LicencePlanKeys.asesoria,
      liveKeys: {'facturacion', 'ai_copilot', 'messaging'},
      plans: [
        LicencePlanInfo(
          key: LicencePlanKeys.asesoria,
          cents: 9900,
          includedKeys: includedKeysForPlan(LicencePlanKeys.asesoria),
        ),
      ],
      catalog: const [
        ModulePrice(key: 'ai_copilot', cents: 1900, alwaysOn: false),
        ModulePrice(key: 'facturacion', cents: 2900, alwaysOn: false),
      ],
    );
    expect(quote.addOns, isEmpty);
    expect(quote.totalCents, 9900);
  });

  test('sleva 100 % je měsíc zdarma', () {
    final quote = resolveLicenceQuote(
      discountBps: 10000,
      planKey: LicencePlanKeys.despacho,
      liveKeys: const {},
      plans: const [
        LicencePlanInfo(
          key: LicencePlanKeys.despacho,
          cents: 6900,
          includedKeys: {'messaging'},
        ),
      ],
      catalog: const [],
    );
    expect(quote.totalCents, 0);
  });

  test('heuristika z faktur je Asesoría', () {
    expect(inferPlanKey({'facturacion'}), LicencePlanKeys.asesoria);
    expect(inferPlanKey({'impuestos'}), LicencePlanKeys.despacho);
    expect(inferPlanKey({'messaging'}), LicencePlanKeys.carpeta);
  });
}
