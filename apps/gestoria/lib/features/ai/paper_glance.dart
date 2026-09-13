import '../../core/money/cents.dart';
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
  });

  final int invoiceCount;
  final int paidCents;
  final PaperGlance? latest;

  /// Od nejstarší po nejnovější. Jen kladné faktury.
  final List<int> bars;
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
  for (final p in papers) {
    final g = paperGlanceOf(tipo: p.tipo, fields: p.fields);
    if (g.isInvoice) invoices.add(g);
  }
  invoices.sort((a, b) => _stamp(b).compareTo(_stamp(a)));
  final paid = invoices.where((g) => g.countsAsPaid).toList();
  final chronological = [...paid]..sort((a, b) => _stamp(a).compareTo(_stamp(b)));
  return PaperStackGlance(
    invoiceCount: invoices.length,
    paidCents: paid.fold<int>(0, (s, g) => s + g.amountCents!),
    latest: invoices.where((g) => g.countsAsPaid).isEmpty
        ? invoices.isEmpty
            ? null
            : invoices.first
        : invoices.firstWhere((g) => g.countsAsPaid),
    bars: [
      for (final g in chronological) g.amountCents!,
    ],
  );
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
