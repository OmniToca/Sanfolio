import '../../core/money/cents.dart';

/// Verze formule. Změní se jen se zákonem, ať staré spisy poznají jiný výpočet.
const kModelo210Formula = 'irnr-210-2026.1';

const modelo210MoneyKeys = <String>{
  'fields.cadastralValue',
  'fields.acquisitionValue',
  'fields.adminValue',
  'fields.rentIncome',
  'fields.expenseIbi',
  'fields.expenseComunidad',
  'fields.expenseInsurance',
  'fields.expenseInterest',
  'fields.expenseRepairs',
  'fields.expenseAgency',
  'fields.expenseOther',
  'fields.constructionValue',
  'fields.salePrice',
  'fields.saleCosts',
  'fields.acquisitionCosts',
  'fields.amortized',
  'fields.withholding211',
  'fields.taxBase',
  'fields.cuota',
  'fields.taxDue',
  'fields.taxWithholding',
};

const modelo210OutputKeys = <String>{
  'fields.taxBase',
  'fields.cuota',
  'fields.taxDue',
  'fields.taxWithholding',
  'fields.taxRate',
  'fields.aeatTipo',
  'fields.taxFormula',
};

/// Pole, která kreslí daňová deska (ne identita spisu).
const modelo210TaxInputKeys = <String>[
  'fields.incomeKind',
  'fields.taxResidency',
  'fields.sharePercent',
  'fields.days',
  'fields.imputeRate',
  'fields.cadastralValue',
  'fields.acquisitionValue',
  'fields.adminValue',
  'fields.rentIncome',
  'fields.expenseIbi',
  'fields.expenseComunidad',
  'fields.expenseInsurance',
  'fields.expenseInterest',
  'fields.expenseRepairs',
  'fields.expenseAgency',
  'fields.expenseOther',
  'fields.constructionValue',
  'fields.multiPayer',
  'fields.salePrice',
  'fields.saleCosts',
  'fields.acquisitionCosts',
  'fields.amortized',
  'fields.withholding211',
  'fields.bought2012',
];

/// Jen vstupy, které teď dávají smysl. Jinak by Jarka vyplňovala prodej u imputace.
List<String> modelo210VisibleInputs(Map<String, String> values) {
  final kind = (values['fields.incomeKind'] ?? '').trim();
  final rate = (values['fields.imputeRate'] ?? '').trim();
  final keys = <String>[
    'fields.incomeKind',
    'fields.taxResidency',
    'fields.sharePercent',
    'fields.days',
  ];
  switch (kind) {
    case 'imputacion':
      keys.add('fields.imputeRate');
      if (rate == 'no_cadastral') {
        keys.addAll(['fields.acquisitionValue', 'fields.adminValue']);
      } else {
        keys.add('fields.cadastralValue');
      }
      break;
    case 'alquiler':
      keys.addAll(const [
        'fields.rentIncome',
        'fields.expenseIbi',
        'fields.expenseComunidad',
        'fields.expenseInsurance',
        'fields.expenseInterest',
        'fields.expenseRepairs',
        'fields.expenseAgency',
        'fields.expenseOther',
        'fields.constructionValue',
        'fields.multiPayer',
      ]);
      break;
    case 'transmision':
      keys.addAll(const [
        'fields.salePrice',
        'fields.saleCosts',
        'fields.acquisitionValue',
        'fields.acquisitionCosts',
        'fields.amortized',
        'fields.withholding211',
        'fields.bought2012',
      ]);
      break;
  }
  return keys;
}

class Modelo210Result {
  const Modelo210Result({
    required this.ok,
    required this.missingKeys,
    required this.aeatTipo,
    required this.taxBaseCents,
    required this.ratePercent,
    required this.cuotaCents,
    required this.withholdingCents,
    required this.taxDueCents,
    required this.formula,
    this.notes = const [],
  });

  final bool ok;
  final List<String> missingKeys;

  /// Kód AEAT: 02 imputace, 01 nájem, 35 nájem víc pagadores, 28 prodej.
  final String aeatTipo;
  final int taxBaseCents;
  final int ratePercent;
  final int cuotaCents;
  final int withholdingCents;

  /// Cuota − srážka. Záporné = a devolver.
  final int taxDueCents;
  final String formula;

  /// i18n klíče vysvětlivek (proč se výdaje nepočítají, 50 % 2012, …).
  final List<String> notes;
}

int yearFromModeloPeriod(String raw) {
  final m = RegExp(r'(\d{4})').firstMatch(raw.trim());
  if (m == null) return 0;
  return int.parse(m.group(1)!);
}

int daysInCalendarYear(int year) {
  if (year < 1900 || year > 2200) return 365;
  return DateTime(year + 1, 1, 1).difference(DateTime(year, 1, 1)).inDays;
}

/// Položka × čitatel / jmenovatel, na cents, polovinu nahoru.
int scaleCents(int cents, int numerator, int denominator) {
  if (denominator == 0) return 0;
  final n = cents * numerator;
  if (n >= 0) return (n + denominator ~/ 2) ~/ denominator;
  return -((-n + denominator ~/ 2) ~/ denominator);
}

Modelo210Result computeModelo210FromFields(Map<String, String> fields) {
  final kind = (fields['fields.incomeKind'] ?? '').trim();
  final residency = (fields['fields.taxResidency'] ?? '').trim();
  final year = yearFromModeloPeriod(fields['fields.modeloPeriod'] ?? '');
  final missing = <String>[];
  if (kind.isEmpty) missing.add('fields.incomeKind');
  if (residency.isEmpty) missing.add('fields.taxResidency');
  if (year == 0) missing.add('fields.modeloPeriod');

  final share = _percent(fields['fields.sharePercent'], fallback: 100);
  if (share == null) missing.add('fields.sharePercent');

  final yearDays = daysInCalendarYear(year == 0 ? 2026 : year);
  final daysRaw = (fields['fields.days'] ?? '').trim();
  var days = yearDays;
  if (daysRaw.isNotEmpty) {
    final d = int.tryParse(daysRaw);
    if (d == null || d < 1 || d > yearDays) {
      missing.add('fields.days');
    } else {
      days = d;
    }
  }

  final aeatTipo = switch (kind) {
    'imputacion' => '02',
    'alquiler' => (fields['fields.multiPayer'] ?? '').trim() == 'yes' ? '35' : '01',
    'transmision' => '28',
    _ => '',
  };

  if (missing.isNotEmpty) {
    return Modelo210Result(
      ok: false,
      missingKeys: missing,
      aeatTipo: aeatTipo,
      taxBaseCents: 0,
      ratePercent: 0,
      cuotaCents: 0,
      withholdingCents: 0,
      taxDueCents: 0,
      formula: '',
    );
  }

  return switch (kind) {
    'imputacion' => _imputacion(
        fields: fields,
        residency: residency,
        share: share!,
        days: days,
        yearDays: yearDays,
      ),
    'alquiler' => _alquiler(
        fields: fields,
        residency: residency,
        share: share!,
        days: days,
        yearDays: yearDays,
        aeatTipo: aeatTipo,
        periodicity: (fields['fields.periodicity'] ?? '').trim(),
      ),
    'transmision' => _transmision(
        fields: fields,
        share: share!,
      ),
    _ => Modelo210Result(
        ok: false,
        missingKeys: const ['fields.incomeKind'],
        aeatTipo: '',
        taxBaseCents: 0,
        ratePercent: 0,
        cuotaCents: 0,
        withholdingCents: 0,
        taxDueCents: 0,
        formula: '',
      ),
  };
}

/// Zápis výsledku na desku. Neúplný vstup smaže staré číslo, ať nelže.
Map<String, String> applyModelo210(Map<String, String> values) {
  final r = computeModelo210FromFields(values);
  final next = Map<String, String>.from(values);
  if (!r.ok) {
    next['fields.taxBase'] = '';
    next['fields.cuota'] = '';
    next['fields.taxDue'] = '';
    next['fields.taxWithholding'] = '';
    next['fields.taxRate'] = '';
    next['fields.aeatTipo'] = r.aeatTipo;
    next['fields.taxFormula'] = '';
    return next;
  }
  next['fields.taxBase'] = '${r.taxBaseCents}';
  next['fields.cuota'] = '${r.cuotaCents}';
  next['fields.taxDue'] = '${r.taxDueCents}';
  next['fields.taxWithholding'] = '${r.withholdingCents}';
  next['fields.taxRate'] = '${r.ratePercent}';
  next['fields.aeatTipo'] = r.aeatTipo;
  next['fields.taxFormula'] = r.formula;
  return next;
}

int _rateForResidency(String residency) => residency == 'ue' ? 19 : 24;

int? _percent(String? raw, {required int fallback}) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return fallback;
  final n = int.tryParse(t.replaceAll(',', '').replaceAll('.', ''));
  if (n == null || n < 1 || n > 100) return null;
  return n;
}

int _money(Map<String, String> fields, String key) {
  return centsFromStored(fields[key]);
}

Modelo210Result _fail(List<String> missing, String aeatTipo) {
  return Modelo210Result(
    ok: false,
    missingKeys: missing,
    aeatTipo: aeatTipo,
    taxBaseCents: 0,
    ratePercent: 0,
    cuotaCents: 0,
    withholdingCents: 0,
    taxDueCents: 0,
    formula: '',
  );
}

/// Imputace (AEAT typ 02). Základ = valor catastral × 1,1 % / 2 %, kráceno dny a podílem.
Modelo210Result _imputacion({
  required Map<String, String> fields,
  required String residency,
  required int share,
  required int days,
  required int yearDays,
}) {
  final rateKey = (fields['fields.imputeRate'] ?? '').trim();
  if (rateKey.isEmpty) return _fail(['fields.imputeRate'], '02');

  int source;
  var note = 'tax.imputeHint';
  if (rateKey == 'no_cadastral') {
    final acq = _money(fields, 'fields.acquisitionValue');
    final admin = _money(fields, 'fields.adminValue');
    if (acq <= 0 && admin <= 0) {
      return _fail(['fields.acquisitionValue'], '02');
    }
    final bigger = acq > admin ? acq : admin;
    source = scaleCents(bigger, 1, 2);
    note = 'tax.noCadastralHint';
  } else {
    source = _money(fields, 'fields.cadastralValue');
    if (source <= 0) return _fail(['fields.cadastralValue'], '02');
  }

  final imputeNum = rateKey == '20' ? 20 : 11;
  var base = scaleCents(source, imputeNum, 1000);
  base = scaleCents(base, days, yearDays);
  base = scaleCents(base, share, 100);
  final rate = _rateForResidency(residency);
  final cuota = scaleCents(base, rate, 100);
  return Modelo210Result(
    ok: true,
    missingKeys: const [],
    aeatTipo: '02',
    taxBaseCents: base,
    ratePercent: rate,
    cuotaCents: cuota,
    withholdingCents: 0,
    taxDueCents: cuota,
    formula: kModelo210Formula,
    notes: [note],
  );
}

/// Nájem (01 / 35). Výdaje a 3 % amortizace stavby jen u rezidenta UE/EEE/LI.
Modelo210Result _alquiler({
  required Map<String, String> fields,
  required String residency,
  required int share,
  required int days,
  required int yearDays,
  required String aeatTipo,
  required String periodicity,
}) {
  final income = _money(fields, 'fields.rentIncome');
  if (income <= 0) return _fail(['fields.rentIncome'], aeatTipo);

  final notes = <String>[];
  var deductible = 0;
  if (residency == 'ue') {
    deductible = _money(fields, 'fields.expenseIbi') +
        _money(fields, 'fields.expenseComunidad') +
        _money(fields, 'fields.expenseInsurance') +
        _money(fields, 'fields.expenseInterest') +
        _money(fields, 'fields.expenseRepairs') +
        _money(fields, 'fields.expenseAgency') +
        _money(fields, 'fields.expenseOther');
    final construction = _money(fields, 'fields.constructionValue');
    if (construction > 0) {
      var amortDays = days;
      if ((fields['fields.days'] ?? '').trim().isEmpty) {
        amortDays = periodicity == 'trimestral' ? (yearDays / 4).round() : yearDays;
      }
      deductible += scaleCents(scaleCents(construction, 3, 100), amortDays, yearDays);
    } else {
      notes.add('tax.noAmortHint');
    }
  } else {
    notes.add('tax.noExpensesOutsideUe');
  }

  var net = income - deductible;
  if (net < 0) net = 0;
  net = scaleCents(net, share, 100);
  final rate = _rateForResidency(residency);
  final cuota = scaleCents(net, rate, 100);
  return Modelo210Result(
    ok: true,
    missingKeys: const [],
    aeatTipo: aeatTipo,
    taxBaseCents: net,
    ratePercent: rate,
    cuotaCents: cuota,
    withholdingCents: 0,
    taxDueCents: cuota,
    formula: kModelo210Formula,
    notes: notes,
  );
}

/// Prodej nemovitosti (typ 28). Sazba 19 % pro všechny. Srážka 3 % modelo 211.
Modelo210Result _transmision({
  required Map<String, String> fields,
  required int share,
}) {
  final sale = _money(fields, 'fields.salePrice');
  if (sale <= 0) return _fail(['fields.salePrice'], '28');
  final acq = _money(fields, 'fields.acquisitionValue');
  if (acq <= 0) return _fail(['fields.acquisitionValue'], '28');

  final transmission = sale - _money(fields, 'fields.saleCosts');
  final acquisition = acq +
      _money(fields, 'fields.acquisitionCosts') -
      _money(fields, 'fields.amortized');
  var gain = transmission - acquisition;
  gain = scaleCents(gain, share, 100);
  final notes = <String>['tax.gainRateHint'];
  if ((fields['fields.bought2012'] ?? '').trim() == 'yes' && gain > 0) {
    gain = scaleCents(gain, 1, 2);
    notes.add('tax.bought2012Hint');
  }
  final base = gain;
  final cuota = base > 0 ? scaleCents(base, 19, 100) : 0;
  var withholding = _money(fields, 'fields.withholding211');
  if (withholding <= 0) {
    withholding = scaleCents(scaleCents(sale, 3, 100), share, 100);
    notes.add('tax.withholdingHint');
  }
  return Modelo210Result(
    ok: true,
    missingKeys: const [],
    aeatTipo: '28',
    taxBaseCents: base,
    ratePercent: 19,
    cuotaCents: cuota,
    withholdingCents: withholding,
    taxDueCents: cuota - withholding,
    formula: kModelo210Formula,
    notes: notes,
  );
}
