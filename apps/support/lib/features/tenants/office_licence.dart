// Komerční licence: 3 balíčky jako OmniToca Mesa/Servicio/Cadena.
// FeatureGate čte organization_modules; tady je jen ceník a included matice.

abstract final class LicencePlanKeys {
  static const carpeta = 'carpeta';
  static const despacho = 'despacho';
  static const asesoria = 'asesoria';

  static const all = [carpeta, despacho, asesoria];
}

/// Doplňky mimo included (Carpeta+AI / Despacho+faktury).
abstract final class LicenceAddonKeys {
  static const all = {'ai_copilot', 'facturacion'};
}

/// Included matice (stejná jako seed 0061). DB může přepsat při načtení.
Set<String> includedKeysForPlan(String planKey) {
  const carpeta = {'carpeta_inmueble', 'messaging'};
  const despacho = {
    ...carpeta,
    'impuestos',
    'nie_poder',
    'policia',
    'ayuntamiento',
    'testament',
    'ofertas',
    'ai_copilot',
  };
  return switch (planKey.trim()) {
    LicencePlanKeys.despacho => despacho,
    LicencePlanKeys.asesoria => {...despacho, 'facturacion'},
    _ => carpeta,
  };
}

/// Heuristika tarifu z živých klíčů, když řádek settings ještě není.
String inferPlanKey(Set<String> live) {
  if (live.contains('facturacion')) return LicencePlanKeys.asesoria;
  const despachoHint = {
    'impuestos',
    'nie_poder',
    'policia',
    'ayuntamiento',
    'testament',
    'ofertas',
    'ai_copilot',
  };
  if (live.any(despachoHint.contains)) return LicencePlanKeys.despacho;
  return LicencePlanKeys.carpeta;
}

class LicencePlanInfo {
  const LicencePlanInfo({
    required this.key,
    required this.cents,
    required this.includedKeys,
  });

  final String key;
  final int cents;
  final Set<String> includedKeys;
}

class LicenceLine {
  const LicenceLine({
    required this.key,
    required this.cents,
    required this.on,
    this.alwaysOn = false,
  });

  final String key;
  final int cents;
  final bool on;
  final bool alwaysOn;
}

class LicenceQuote {
  const LicenceQuote({
    this.planKey = LicencePlanKeys.carpeta,
    this.planCents = 0,
    this.plans = const [],
    this.addOns = const [],
    this.includedKeys = const {},
    this.discountBps = 0,
  });

  final String planKey;
  final int planCents;
  final List<LicencePlanInfo> plans;
  final List<LicenceLine> addOns;
  final Set<String> includedKeys;
  final int discountBps;

  /// Cena balíčku + doplňky, které nejsou v included.
  int get subtotalCents {
    var n = planCents < 0 ? 0 : planCents;
    for (final line in addOns) {
      if (line.on) n += line.cents;
    }
    return n;
  }

  int get clampedBps {
    if (discountBps < 0) return 0;
    if (discountBps > 10000) return 10000;
    return discountBps;
  }

  int get discountCents => (subtotalCents * clampedBps / 10000).round();

  int get totalCents => subtotalCents - discountCents;

  int get discountPercent => (clampedBps / 100).round();
}

class ModulePrice {
  const ModulePrice({
    required this.key,
    required this.cents,
    required this.alwaysOn,
  });

  final String key;
  final int cents;
  final bool alwaysOn;
}

/// Měsíční celkem: cena plánu + add-ony mimo included. Ne součet ceníku modulů.
LicenceQuote resolveLicenceQuote({
  required List<LicencePlanInfo> plans,
  required String planKey,
  required Set<String> liveKeys,
  required List<ModulePrice> catalog,
  int discountBps = 0,
}) {
  final resolved = planKey.trim().isEmpty
      ? inferPlanKey(liveKeys)
      : planKey.trim();
  LicencePlanInfo? match;
  for (final p in plans) {
    if (p.key == resolved) {
      match = p;
      break;
    }
  }
  final included = match?.includedKeys ?? includedKeysForPlan(resolved);
  final cents = match?.cents ?? 0;
  final addOns = <LicenceLine>[
    for (final row in catalog)
      if (LicenceAddonKeys.all.contains(row.key) && !included.contains(row.key))
        LicenceLine(
          key: row.key,
          cents: row.cents,
          on: liveKeys.contains(row.key),
        ),
  ];
  return LicenceQuote(
    planKey: resolved,
    planCents: cents < 0 ? 0 : cents,
    plans: plans,
    addOns: addOns,
    includedKeys: included,
    discountBps: discountBps,
  );
}
