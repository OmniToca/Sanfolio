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

/// Řádek office-wide fronty: platí víc než nejlevnější tarif kanceláře.
class OverpayRow {
  const OverpayRow({
    required this.clienteId,
    required this.clienteNombre,
    required this.bloqueKey,
    required this.clientAnnualCents,
    required this.offerTitle,
    required this.offerAnnualCents,
    required this.savingCents,
    this.expedienteId,
    this.offerId,
  });

  final String clienteId;
  final String clienteNombre;
  final String bloqueKey;
  final String? expedienteId;
  final int clientAnnualCents;
  final String? offerId;
  final String offerTitle;
  final int offerAnnualCents;
  final int savingCents;
}

/// Nejlevnější nabídka, u které klient přeplácí. Voda sem nepatří.
OverpayRow? overpayOf({
  required String clienteId,
  required String clienteNombre,
  required String bloqueKey,
  required PaperStackGlance glance,
  required List<OfficeOffer> offers,
  String? expedienteId,
}) {
  final lines = compareOfficeOffers(
    bloqueKey: bloqueKey,
    glance: glance,
    offers: offers,
  );
  for (final line in lines) {
    final saving = line.savingCents;
    if (saving == null || saving <= 0) continue;
    if (line.clientAnnualCents == null || line.offerAnnualCents == null) {
      continue;
    }
    return OverpayRow(
      clienteId: clienteId,
      clienteNombre: clienteNombre,
      bloqueKey: bloqueKey,
      expedienteId: expedienteId,
      clientAnnualCents: line.clientAnnualCents!,
      offerId: line.offer.id,
      offerTitle: line.offer.title,
      offerAnnualCents: line.offerAnnualCents!,
      savingCents: saving,
    );
  }
  return null;
}

OverpayRow? overpayRowFromRpc(Map raw) {
  final clienteId = '${raw['cliente_id'] ?? ''}'.trim();
  final bloqueKey = '${raw['bloque_key'] ?? ''}'.trim();
  final clientAnnual = _intOrNull(raw['client_annual_cents']);
  final offerAnnual = _intOrNull(raw['offer_annual_cents']);
  final saving = _intOrNull(raw['saving_cents']);
  final title = '${raw['offer_title'] ?? ''}'.trim();
  if (clienteId.isEmpty ||
      !offerKindForBloque(bloqueKey) ||
      clientAnnual == null ||
      offerAnnual == null ||
      saving == null ||
      saving <= 0 ||
      title.isEmpty) {
    return null;
  }
  final exp = '${raw['expediente_id'] ?? ''}'.trim();
  final offerId = '${raw['offer_id'] ?? ''}'.trim();
  return OverpayRow(
    clienteId: clienteId,
    clienteNombre: '${raw['cliente_nombre'] ?? ''}'.trim(),
    bloqueKey: bloqueKey,
    expedienteId: exp.isEmpty ? null : exp,
    clientAnnualCents: clientAnnual,
    offerId: offerId.isEmpty ? null : offerId,
    offerTitle: title,
    offerAnnualCents: offerAnnual,
    savingCents: saving,
  );
}
