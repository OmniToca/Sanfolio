/// Peníze v DB jsou integer cents. UI ukáže eura s čárkou.
int? parseEurosToCents(String raw) {
  var t = raw.trim().replaceAll(' ', '').replaceAll('\u00A0', '');
  if (t.isEmpty) return null;
  final lastComma = t.lastIndexOf(',');
  final lastDot = t.lastIndexOf('.');
  if (lastComma > lastDot) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  } else {
    t = t.replaceAll(',', '');
  }
  final n = double.tryParse(t);
  if (n == null) return null;
  return (n * 100).round();
}

String formatCents(int cents) {
  final sign = cents < 0 ? '-' : '';
  final a = cents.abs();
  final euros = a ~/ 100;
  final rest = (a % 100).toString().padLeft(2, '0');
  return '$sign$euros,$rest';
}
