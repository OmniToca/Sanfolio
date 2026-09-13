import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/expedientes/modelo_210.dart';

void main() {
  test('AEAT příklad imputace 60 100 € × 1,1 % × 19 %', () {
    final r = computeModelo210FromFields({
      'fields.incomeKind': 'imputacion',
      'fields.taxResidency': 'ue',
      'fields.modeloPeriod': '2018',
      'fields.imputeRate': '11',
      'fields.cadastralValue': '6010000',
    });
    expect(r.ok, isTrue);
    expect(r.aeatTipo, '02');
    expect(r.taxBaseCents, 66110);
    expect(r.ratePercent, 19);
    expect(r.cuotaCents, 12561);
    expect(r.taxDueCents, 12561);
    expect(r.formula, kModelo210Formula);
  });

  test('imputace 2 % mimo UE, polovina roku, 50 % podíl', () {
    final r = computeModelo210FromFields({
      'fields.incomeKind': 'imputacion',
      'fields.taxResidency': 'other',
      'fields.modeloPeriod': '2026',
      'fields.imputeRate': '20',
      'fields.cadastralValue': '10000000',
      'fields.sharePercent': '50',
      'fields.days': '182',
    });
    expect(r.ok, isTrue);
    expect(r.ratePercent, 24);
    // 100 000 × 2 % = 2000; × 182/365 × 50 % 
    expect(r.taxBaseCents, 49863);
    expect(r.cuotaCents, 11967);
  });

  test('bez catastral bere 50 % vyšší z nabytí a úřadu × 1,1 %', () {
    final r = computeModelo210FromFields({
      'fields.incomeKind': 'imputacion',
      'fields.taxResidency': 'ue',
      'fields.modeloPeriod': '2025',
      'fields.imputeRate': 'no_cadastral',
      'fields.acquisitionValue': '20000000',
      'fields.adminValue': '15000000',
    });
    expect(r.ok, isTrue);
    expect(r.taxBaseCents, 110000);
    expect(r.cuotaCents, 20900);
  });

  test('nájem UE odečte výdaje a 3 % amortizace stavby', () {
    final r = computeModelo210FromFields({
      'fields.incomeKind': 'alquiler',
      'fields.taxResidency': 'ue',
      'fields.modeloPeriod': '2026',
      'fields.periodicity': 'anual',
      'fields.rentIncome': '1200000',
      'fields.expenseIbi': '40000',
      'fields.constructionValue': '10000000',
    });
    expect(r.ok, isTrue);
    expect(r.aeatTipo, '01');
    // 12 000 − 400 − 3 000 = 8 600
    expect(r.taxBaseCents, 860000);
    expect(r.cuotaCents, 163400);
  });

  test('nájem mimo UE výdaje nebere a sazba je 24 %', () {
    final r = computeModelo210FromFields({
      'fields.incomeKind': 'alquiler',
      'fields.taxResidency': 'other',
      'fields.modeloPeriod': '2026',
      'fields.rentIncome': '1200000',
      'fields.expenseIbi': '40000',
      'fields.constructionValue': '10000000',
    });
    expect(r.ok, isTrue);
    expect(r.taxBaseCents, 1200000);
    expect(r.ratePercent, 24);
    expect(r.cuotaCents, 288000);
    expect(r.notes, contains('tax.noExpensesOutsideUe'));
  });

  test('víc nájemců je AEAT typ 35', () {
    final r = computeModelo210FromFields({
      'fields.incomeKind': 'alquiler',
      'fields.taxResidency': 'ue',
      'fields.modeloPeriod': '2026',
      'fields.rentIncome': '100000',
      'fields.multiPayer': 'yes',
    });
    expect(r.aeatTipo, '35');
  });

  test('prodej: zisk 19 %, srážka 3 %, 50 % osvobození 2012', () {
    final r = computeModelo210FromFields({
      'fields.incomeKind': 'transmision',
      'fields.taxResidency': 'ue',
      'fields.modeloPeriod': '2026',
      'fields.salePrice': '30000000',
      'fields.saleCosts': '1000000',
      'fields.acquisitionValue': '20000000',
      'fields.acquisitionCosts': '2000000',
      'fields.bought2012': 'yes',
    });
    expect(r.ok, isTrue);
    expect(r.aeatTipo, '28');
    expect(r.ratePercent, 19);
    // (300k − 10k) − (200k + 20k) = 70k, polovina 2012 = 35k
    expect(r.taxBaseCents, 3500000);
    expect(r.cuotaCents, 665000);
    expect(r.withholdingCents, 900000);
    expect(r.taxDueCents, -235000);
  });

  test('bez druhu příjmu se nepočítá', () {
    final r = computeModelo210FromFields({
      'fields.modeloPeriod': '2026',
    });
    expect(r.ok, isFalse);
    expect(r.missingKeys, containsAll(['fields.incomeKind', 'fields.taxResidency']));
  });

  test('apply smaže staré číslo, když chybí vstup', () {
    final out = applyModelo210({
      'fields.taxBase': '999',
      'fields.modeloPeriod': '2026',
    });
    expect(out['fields.taxBase'], '');
    expect(out['fields.taxFormula'], '');
  });
}
