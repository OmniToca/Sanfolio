/// Měsíční licence: součet ceníku zapnutých služeb minus sleva kanceláře.
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

  bool get billed => alwaysOn || on;
}

class LicenceQuote {
  const LicenceQuote({
    required this.lines,
    this.discountBps = 0,
  });

  final List<LicenceLine> lines;
  final int discountBps;

  int get subtotalCents {
    var n = 0;
    for (final line in lines) {
      if (line.billed) n += line.cents;
    }
    return n;
  }

  int get clampedBps {
    if (discountBps < 0) return 0;
    if (discountBps > 10000) return 10000;
    return discountBps;
  }

  int get discountCents =>
      (subtotalCents * clampedBps / 10000).round();

  int get totalCents => subtotalCents - discountCents;

  int get discountPercent => (clampedBps / 100).round();
}
