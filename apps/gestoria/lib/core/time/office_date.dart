/// Termíny jsou kalendářní den (Europe/Madrid), ne timestamptz.
/// Špatný OCR string není alert — vrátí null.

enum ExpiryTone { valid, expiring, expired }

DateTime? parseOfficeDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (iso != null) {
    return _ymd(
      int.parse(iso[1]!),
      int.parse(iso[2]!),
      int.parse(iso[3]!),
    );
  }
  final dmy = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$').firstMatch(s);
  if (dmy != null) {
    return _ymd(
      int.parse(dmy[3]!),
      int.parse(dmy[2]!),
      int.parse(dmy[1]!),
    );
  }
  final ymd = RegExp(r'^(\d{4})[./](\d{1,2})[./](\d{1,2})$').firstMatch(s);
  if (ymd != null) {
    return _ymd(
      int.parse(ymd[1]!),
      int.parse(ymd[2]!),
      int.parse(ymd[3]!),
    );
  }
  return null;
}

DateTime? _ymd(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, m, d);
  if (dt.year != y || dt.month != m || dt.day != d) return null;
  return dt;
}

DateTime calendarDay(DateTime t) => DateTime(t.year, t.month, t.day);

/// DATE v Postgres. OCR / pole formuláře → ISO, jinak null.
String? toIsoDate(String? raw) {
  final parsed = parseOfficeDate(raw ?? '');
  if (parsed == null) return null;
  return formatIsoDate(parsed);
}

String formatIsoDate(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

String todayIsoDate([DateTime? now]) => formatIsoDate(calendarDay(now ?? DateTime.now()));

/// [warnDays] z tenant_settings. 0 = jen prošlé vs. platné, bez „brzy“.
ExpiryTone? expiryTone({
  required String raw,
  required DateTime today,
  required int warnDays,
}) {
  final parsed = parseOfficeDate(raw);
  if (parsed == null) return null;
  final expiry = calendarDay(parsed);
  final day = calendarDay(today);
  if (expiry.isBefore(day)) return ExpiryTone.expired;
  if (warnDays > 0) {
    final warnFrom = expiry.subtract(Duration(days: warnDays));
    if (!day.isBefore(warnFrom)) return ExpiryTone.expiring;
  }
  return ExpiryTone.valid;
}
