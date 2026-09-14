/// Španělské sazby IVA na razítkách. 0 = exenta / bez DPH.
const kIvaRatesBps = [2100, 1000, 400, 0];

/// Obchodní řádek vydané. Verifacti dostane součet podle sazby, ne tyto položky.
class FacturaLinea {
  const FacturaLinea({
    required this.descripcion,
    required this.cantidad,
    required this.precioUnitarioCents,
    required this.ivaBps,
    this.descuentoBps = 0,
  });

  final String descripcion;
  final double cantidad;
  final int precioUnitarioCents;
  final int ivaBps;
  final int descuentoBps;

  int get grossCents => (cantidad * precioUnitarioCents).round();

  int get baseCents =>
      ((grossCents * (10000 - descuentoBps.clamp(0, 10000))) / 10000).round();

  int get ivaCents => ((baseCents * ivaBps) / 10000).round();

  int get totalCents => baseCents + ivaCents;

  bool get isBlank =>
      descripcion.trim().isEmpty && baseCents == 0 && precioUnitarioCents == 0;

  Map<String, Object?> toJson() => {
        'descripcion': descripcion.trim(),
        'cantidad': cantidadString(cantidad),
        'precio_cents': precioUnitarioCents,
        'iva_bps': ivaBps,
        'descuento_bps': descuentoBps,
        'base_cents': baseCents,
        'iva_cents': ivaCents,
      };

  factory FacturaLinea.fromJson(Map<dynamic, dynamic> raw) {
    return FacturaLinea(
      descripcion: '${raw['descripcion'] ?? ''}'.trim(),
      cantidad: parseQuantity('${raw['cantidad'] ?? '1'}') ?? 1,
      precioUnitarioCents: _int(raw['precio_cents']),
      ivaBps: _int(raw['iva_bps'], fallback: 2100),
      descuentoBps: _int(raw['descuento_bps']),
    );
  }
}

class IvaBreakdown {
  const IvaBreakdown({
    required this.ivaBps,
    required this.baseCents,
    required this.ivaCents,
  });

  final int ivaBps;
  final int baseCents;
  final int ivaCents;

  int get totalCents => baseCents + ivaCents;
}

/// Součty knihy a vstupy pro Verifacti `lineas` (max 12 sazeb).
class FacturaTotales {
  const FacturaTotales({
    required this.lineas,
    required this.byRate,
    required this.baseCents,
    required this.ivaCents,
    required this.totalCents,
  });

  final List<FacturaLinea> lineas;
  final List<IvaBreakdown> byRate;
  final int baseCents;
  final int ivaCents;
  final int totalCents;

  int? get dominantIvaBps {
    if (byRate.isEmpty) return null;
    return byRate.reduce((a, b) => a.baseCents >= b.baseCents ? a : b).ivaBps;
  }

  bool get isEmpty => lineas.isEmpty || totalCents <= 0;

  /// F2 zjednodušená: AEAT limit 3000 €.
  bool get exceedsF2Limit => totalCents > 300000;
}

FacturaTotales totalsFromLineas(Iterable<FacturaLinea> raw) {
  final lineas = [for (final l in raw) if (!l.isBlank) l];
  final acc = <int, IvaBreakdown>{};
  for (final line in lineas) {
    final prev = acc[line.ivaBps];
    acc[line.ivaBps] = IvaBreakdown(
      ivaBps: line.ivaBps,
      baseCents: (prev?.baseCents ?? 0) + line.baseCents,
      ivaCents: (prev?.ivaCents ?? 0) + line.ivaCents,
    );
  }
  final byRate = acc.values.toList()
    ..sort((a, b) => b.ivaBps.compareTo(a.ivaBps));
  var base = 0;
  var iva = 0;
  for (final row in byRate) {
    base += row.baseCents;
    iva += row.ivaCents;
  }
  return FacturaTotales(
    lineas: lineas,
    byRate: byRate,
    baseCents: base,
    ivaCents: iva,
    totalCents: base + iva,
  );
}

/// Množství: 1,5 i 1.5. Prázdné = null, ne nula (řádek bez qty přeskočí UI).
double? parseQuantity(String raw) {
  var t = raw.trim().replaceAll(' ', '').replaceAll('\u00A0', '');
  if (t.isEmpty) return null;
  final lastComma = t.lastIndexOf(',');
  final lastDot = t.lastIndexOf('.');
  if (lastComma > lastDot) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  } else {
    t = t.replaceAll(',', '');
  }
  return double.tryParse(t);
}

/// Sleva 10 nebo 10,5 → bps. Nad 100 % seřízne UI.
int parsePercentToBps(String raw) {
  final q = parseQuantity(raw);
  if (q == null || q <= 0) return 0;
  final bps = (q * 100).round();
  if (bps > 10000) return 10000;
  return bps;
}

String ivaRateLabel(int bps) => '${bps / 100}%'.replaceAll('.0%', '%');

String cantidadString(double qty) {
  if (qty == qty.roundToDouble()) return '${qty.round()}';
  final s = qty.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '');
  return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
}

int _int(Object? v, {int fallback = 0}) {
  if (v is int) return v;
  return int.tryParse('$v') ?? fallback;
}
