import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/modules/module_catalog.dart';
import 'package:gestoria_os/features/ai/paper_glance.dart';
import 'package:gestoria_os/features/mensajes/mensaje_templates.dart';
import 'package:gestoria_os/features/ofertas/office_offers.dart';

void main() {
  test('modul ofertas má klíč do organization_modules, ne do railu', () {
    expect(GestoriaModule.ofertas.key, 'ofertas');
    expect(GestoriaModuleKey.fromKey('ofertas'), GestoriaModule.ofertas);
  });

  test('srovnání na bloku luz bere roční odhad z faktur a nabídky kanceláře', () {
    final glance = stackGlanceOf([
      (
        tipo: 'factura_luz',
        fields: {
          'fields.amount': '100.00',
          'fields.consumption': '500 kWh',
          'fields.periodFrom': '2026-01-01',
          'fields.periodTo': '2026-02-01',
        },
      ),
    ]);
    const cheap = OfficeOffer(
      id: '1',
      kind: 'luz',
      title: 'Barata 2.0TD',
      unitCents: 10,
      annualCents: 80000,
    );
    const other = OfficeOffer(
      id: '2',
      kind: 'gaz',
      title: 'Plyn mimo blok',
      annualCents: 10000,
    );
    final lines = compareOfficeOffers(
      bloqueKey: 'luz',
      glance: glance,
      offers: const [cheap, other],
    );
    expect(lines.length, 1);
    expect(lines.first.offer.title, 'Barata 2.0TD');
    expect(lines.first.clientAnnualCents, isNotNull);
    expect(lines.first.offerAnnualCents, 80000);
    expect(offerKindForBloque('agua'), isFalse);
  });

  test('Nachystat výzvu je šablona compose, ne odeslání', () {
    expect(mensajeTemplateByKey('oferta_suministro')?.key, 'oferta_suministro');
    expect(
      fillMensajeTemplate('valorar {{documento}}', {'documento': 'Barata 2.0TD'}),
      'valorar Barata 2.0TD',
    );
  });

  test('office-wide fronta bere jen kdo z faktur přeplácí tarif kanceláře', () {
    final glance = stackGlanceOf([
      (
        tipo: 'factura_luz',
        fields: {
          'fields.amount': '200.00',
          'fields.consumption': '1000 kWh',
          'fields.periodFrom': '2026-01-01',
          'fields.periodTo': '2026-02-01',
        },
      ),
    ]);
    const cheap = OfficeOffer(
      id: '1',
      kind: 'luz',
      title: 'Barata 2.0TD',
      annualCents: 80000,
    );
    const dear = OfficeOffer(
      id: '2',
      kind: 'luz',
      title: 'Drahá',
      annualCents: 900000,
    );
    final hit = overpayOf(
      clienteId: 'c1',
      clienteNombre: 'Ana',
      bloqueKey: 'luz',
      glance: glance,
      offers: const [cheap, dear],
    );
    expect(hit, isNotNull);
    expect(hit!.offerTitle, 'Barata 2.0TD');
    expect(hit.savingCents, greaterThan(0));
    expect(
      overpayOf(
        clienteId: 'c1',
        clienteNombre: 'Ana',
        bloqueKey: 'luz',
        glance: glance,
        offers: const [dear],
      ),
      isNull,
    );
    expect(
      overpayOf(
        clienteId: 'c1',
        clienteNombre: 'Ana',
        bloqueKey: 'agua',
        glance: glance,
        offers: const [cheap],
      ),
      isNull,
    );
  });
}
