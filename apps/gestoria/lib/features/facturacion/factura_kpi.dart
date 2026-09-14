import '../../core/time/office_date.dart';
import 'factura.dart';

/// Součty knihy jako v účetním přehledu. Jen z už načtených řádků, ne druhý SQL.
class LibroKpi {
  const LibroKpi({
    required this.year,
    required this.count,
    required this.totalCents,
    required this.overdueCount,
    required this.overdueCents,
    required this.pendingCount,
    required this.dueSoonCount,
  });

  final int year;
  final int count;
  final int totalCents;
  final int overdueCount;
  final int overdueCents;
  final int pendingCount;
  final int dueSoonCount;
}

LibroKpi libroKpi(
  Iterable<Factura> rows, {
  required DateTime today,
  required bool emitidas,
}) {
  final day = calendarDay(today);
  final year = day.year;
  var count = 0;
  var total = 0;
  var overdueN = 0;
  var overdueCents = 0;
  var pending = 0;
  var dueSoon = 0;
  for (final row in rows) {
    if (row.estado == 'anulada') continue;
    final fecha = parseOfficeDate(row.fecha ?? '');
    if (fecha == null || fecha.year != year) continue;
    count += 1;
    total += row.totalCents;
    if (emitidas && (row.estado == 'pendiente' || row.estado == 'error')) {
      pending += 1;
    }
    final venc = parseOfficeDate(row.vencimiento ?? '');
    if (venc == null) continue;
    final due = calendarDay(venc);
    if (due.isBefore(day)) {
      overdueN += 1;
      overdueCents += row.totalCents;
    } else {
      dueSoon += 1;
    }
  }
  return LibroKpi(
    year: year,
    count: count,
    totalCents: total,
    overdueCount: overdueN,
    overdueCents: overdueCents,
    pendingCount: pending,
    dueSoonCount: dueSoon,
  );
}
