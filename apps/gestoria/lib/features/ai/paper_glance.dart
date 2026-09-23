import '../../core/money/cents.dart';
import '../../core/time/office_date.dart';
import 'documento_fields.dart';
import 'extract_text.dart';

/// Pole identity žijí na desce. Na faktuře se neopakují.
const kPaperIdentityKeys = {
  'fields.nombre',
  'fields.company',
  'fields.holder',
  'fields.cups',
  'fields.clientNo',
  'fields.contractNo',
};

/// Jeden papír ve stohu — UI i asistent čtou totéž.
class PaperGlance {
  const PaperGlance({
    required this.tipo,
    this.periodFrom,
    this.periodTo,
    this.amountCents,
    this.consumption,
    this.invoiceNo,
    this.issued,
  });

  final String tipo;
  final String? periodFrom;
  final String? periodTo;
  final int? amountCents;
  final String? consumption;
  final String? invoiceNo;
  final String? issued;

  bool get isInvoice => isInvoiceDocTipo(tipo);

  /// Kladná faktura jde do součtu. Dobropis (zápor) je sleva, ne náklad.
  bool get countsAsPaid =>
      isInvoice && amountCents != null && amountCents! > 0;
}

/// Přehled stohu: kolik faktur, kolik sečetlo, poslední období, sloupečky v čase.
class PaperStackGlance {
  const PaperStackGlance({
    required this.invoiceCount,
    required this.paidCents,
    this.latest,
    this.bars = const [],
    this.effectiveUnitCents,
    this.annualCentsEstimate,
    this.yearlyConsumption,
    this.policyPremiumCents,
  });

  final int invoiceCount;
  final int paidCents;
  final PaperGlance? latest;

  /// Od nejstarší po nejnovější. Jen kladné faktury.
  final List<int> bars;

  /// Cents za 1 kWh nebo m³ z kladných faktur se spotřebou.
  final int? effectiveUnitCents;

  /// Roční odhad z poslední faktury s obdobím. Není to ceník trhu.
  final int? annualCentsEstimate;

  /// Roční spotřeba z poslední faktury s kWh/m³ a obdobím.
  final double? yearlyConsumption;

  /// Prémie z pólizy (roční, nebo anualizovaná).
  final int? policyPremiumCents;
}

PaperGlance paperGlanceOf({
  required String tipo,
  required Map<String, String> fields,
}) {
  final amountRaw = (fields['fields.amount'] ?? '').trim();
  return PaperGlance(
    tipo: tipo,
    periodFrom: _opt(fields['fields.periodFrom']),
    periodTo: _opt(fields['fields.periodTo']),
    amountCents: amountRaw.isEmpty ? null : centsFromStored(amountRaw),
    consumption: _opt(fields['fields.consumption']),
    invoiceNo: _opt(fields['fields.invoiceNo']),
    issued: _opt(fields['fields.issued']),
  );
}

PaperStackGlance stackGlanceOf(
  Iterable<({String tipo, Map<String, String> fields})> papers,
) {
  final invoices = <PaperGlance>[];
  final policies = <PaperGlance>[];
  for (final p in papers) {
    final g = paperGlanceOf(tipo: p.tipo, fields: p.fields);
    if (g.isInvoice) invoices.add(g);
    if (p.tipo == 'poliza_seguro' &&
        g.amountCents != null &&
        g.amountCents! > 0) {
      policies.add(g);
    }
  }
  invoices.sort((a, b) => _stamp(b).compareTo(_stamp(a)));
  policies.sort((a, b) => _stamp(b).compareTo(_stamp(a)));
  final paid = invoices.where((g) => g.countsAsPaid).toList();
  final chronological = [...paid]..sort((a, b) => _stamp(a).compareTo(_stamp(b)));
  final latestPaid = paid.isEmpty ? null : invoices.firstWhere((g) => g.countsAsPaid);
  return PaperStackGlance(
    invoiceCount: invoices.length,
    paidCents: paid.fold<int>(0, (s, g) => s + g.amountCents!),
    latest: latestPaid ?? (invoices.isEmpty ? null : invoices.first),
    bars: [
      for (final g in chronological) g.amountCents!,
    ],
    effectiveUnitCents: effectiveUnitCentsOf(paid),
    annualCentsEstimate: latestPaid == null ? null : annualCentsOf(latestPaid),
    yearlyConsumption:
        latestPaid == null ? null : yearlyConsumptionOf(latestPaid),
    policyPremiumCents: policies.isEmpty
        ? null
        : annualCentsOf(policies.first, treatBareAsAnnual: true),
  );
}

/// Cents / jednotka ze součtu částek a spotřeb. Bez spotřeby nic nevymýšlíme.
int? effectiveUnitCentsOf(Iterable<PaperGlance> paid) {
  var cents = 0;
  var qty = 0.0;
  for (final g in paid) {
    final q = parseConsumptionQty(g.consumption);
    if (q == null || q <= 0 || g.amountCents == null) continue;
    cents += g.amountCents!;
    qty += q;
  }
  if (qty <= 0) return null;
  return (cents / qty).round();
}

int? annualCentsOf(PaperGlance g, {bool treatBareAsAnnual = false}) {
  if (g.amountCents == null || g.amountCents! <= 0) return null;
  final days = periodDaysOf(g);
  if (days == null || days <= 0) {
    return treatBareAsAnnual ? g.amountCents : null;
  }
  return ((g.amountCents! * 365) / days).round();
}

double? yearlyConsumptionOf(PaperGlance g) {
  final q = parseConsumptionQty(g.consumption);
  if (q == null || q <= 0) return null;
  final days = periodDaysOf(g);
  if (days == null || days <= 0) return q;
  return q * 365 / days;
}

/// Španělská obecní voda (Hidraqua, Aqualia, …) se skoro vždy fakturuje
/// kvartálně. OCR často vezme jeden měsíc z grafu spotřeby, ne Periodo de
/// facturación — roční odhad by šel ×4.
const kAguaQuarterDays = 91;
const kAguaShortPeriodDays = 45;

int? periodDaysOf(PaperGlance g) {
  final from = parseOfficeDate(g.periodFrom ?? '');
  final to = parseOfficeDate(g.periodTo ?? '');
  if (from == null || to == null) return null;
  final days = to.difference(from).inDays;
  if (days <= 0) return null;
  if (_aguaUsesQuarterFallback(g.tipo) && days < kAguaShortPeriodDays) {
    return kAguaQuarterDays;
  }
  return days;
}

bool _aguaUsesQuarterFallback(String tipo) {
  return tipo == 'factura_agua' || tipo == 'recibo_agua';
}

/// „1120 kWh“, „12,5 m³“. Bez jednotky pořád číslo.
double? parseConsumptionQty(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return null;
  final m = RegExp(r'([\d]+(?:[.,]\d+)?)').firstMatch(s.replaceAll(' ', ''));
  if (m == null) return null;
  final n = parseEurosToCents(m[1]!);
  if (n == null) return null;
  return n / 100.0;
}

/// kWh u elektřiny/plynu, m³ u vody. Vodu nesrovnáváme.
String supplyMeasureKey(String bloqueKey) {
  return bloqueKey == 'agua' ? 'folder.measureM3' : 'folder.measureKwh';
}

bool offerKindForBloque(String bloqueKey) {
  return bloqueKey == 'luz' || bloqueKey == 'gaz' || bloqueKey == 'seguro';
}

String? paperPeriodRaw(PaperGlance g) {
  final from = g.periodFrom ?? '';
  final to = g.periodTo ?? '';
  if (from.isEmpty && to.isEmpty) return null;
  if (from.isEmpty) return to;
  if (to.isEmpty) return from;
  return '$from – $to';
}

List<String> extraPaperFieldKeys(Map<String, String> fields, {String tipo = ''}) {
  final skip = {
    ...kPaperIdentityKeys,
    'fields.amount',
    'fields.periodFrom',
    'fields.periodTo',
    'fields.consumption',
    'fields.invoiceNo',
    'body_text',
    kExtractStatus,
    'fields.folderLado',
  };
  if (tipo == 'copia_escritura') skip.remove('fields.nombre');
  return [
    for (final e in fields.entries)
      if (e.value.trim().isNotEmpty && !skip.contains(e.key)) e.key,
  ];
}

String _stamp(PaperGlance g) =>
    (g.periodTo ?? g.issued ?? g.periodFrom ?? '').trim();

String? _opt(String? raw) {
  final v = (raw ?? '').trim();
  return v.isEmpty ? null : v;
}
