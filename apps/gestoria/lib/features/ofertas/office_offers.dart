import '../ai/paper_glance.dart';

/// Tarif, který kancelář sama vyplnila. Není to ceník trhu.
class OfficeOffer {
  const OfficeOffer({
    required this.id,
    required this.kind,
    required this.title,
    this.partner = '',
    this.unitCents,
    this.annualCents,
    this.notes = '',
  });

  final String id;
  final String kind;
  final String title;
  final String partner;
  final int? unitCents;
  final int? annualCents;
  final String notes;

  bool get isEnergy => kind == 'luz' || kind == 'gaz';
}

const officeOfferKinds = ['luz', 'gaz', 'seguro'];

/// Srovnání na bloku: kolik platí teď vs. nabídka kanceláře.
class OfferCompareLine {
  const OfferCompareLine({
    required this.offer,
    this.clientAnnualCents,
    this.offerAnnualCents,
    this.clientUnitCents,
    this.offerUnitCents,
  });

  final OfficeOffer offer;
  final int? clientAnnualCents;
  final int? offerAnnualCents;
  final int? clientUnitCents;
  final int? offerUnitCents;

  int? get savingCents {
    final a = clientAnnualCents;
    final b = offerAnnualCents;
    if (a == null || b == null) return null;
    return a - b;
  }
}

OfficeOffer? officeOfferFromRow(Map raw) {
  final id = '${raw['id'] ?? ''}'.trim();
  final kind = '${raw['kind'] ?? ''}'.trim();
  final title = '${raw['title'] ?? ''}'.trim();
  if (id.isEmpty || title.isEmpty || !officeOfferKinds.contains(kind)) {
    return null;
  }
  return OfficeOffer(
    id: id,
    kind: kind,
    title: title,
    partner: '${raw['partner'] ?? ''}'.trim(),
    unitCents: _intOrNull(raw['unit_cents']),
    annualCents: _intOrNull(raw['annual_cents']),
    notes: '${raw['notes'] ?? ''}'.trim(),
  );
}

List<OfferCompareLine> compareOfficeOffers({
  required String bloqueKey,
  required PaperStackGlance glance,
  required List<OfficeOffer> offers,
}) {
  if (!offerKindForBloque(bloqueKey)) return const [];
  final kind = bloqueKey == 'gaz' ? 'gaz' : bloqueKey;
  final clientAnnual = bloqueKey == 'seguro'
      ? glance.policyPremiumCents
      : glance.annualCentsEstimate;
  final clientUnit = bloqueKey == 'seguro' ? null : glance.effectiveUnitCents;
  final lines = <OfferCompareLine>[];
  for (final o in offers) {
    if (o.kind != kind) continue;
    lines.add(
      OfferCompareLine(
        offer: o,
        clientAnnualCents: clientAnnual,
        offerAnnualCents: _offerAnnual(o, glance),
        clientUnitCents: clientUnit,
        offerUnitCents: o.unitCents,
      ),
    );
  }
  lines.sort((a, b) {
    final aa = a.offerAnnualCents;
    final bb = b.offerAnnualCents;
    if (aa == null && bb == null) return a.offer.title.compareTo(b.offer.title);
    if (aa == null) return 1;
    if (bb == null) return -1;
    return aa.compareTo(bb);
  });
  return lines;
}

int? _offerAnnual(OfficeOffer offer, PaperStackGlance glance) {
  if (offer.annualCents != null) return offer.annualCents;
  final unit = offer.unitCents;
  final kwh = glance.yearlyConsumption;
  if (unit == null || kwh == null || kwh <= 0) return null;
  return (unit * kwh).round();
}

int? _intOrNull(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  return int.tryParse('$raw');
}
