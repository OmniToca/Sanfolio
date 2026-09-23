import '../../core/time/office_date.dart';

/// Přehled plné moci. Pravda je kopie papíru, ne zapnutý blok desky.
enum PoderGlanceKind { missing, present, expiring, expired }

class PoderGlance {
  const PoderGlance({
    this.kind = PoderGlanceKind.missing,
    this.expiresOn,
  });

  final PoderGlanceKind kind;
  final DateTime? expiresOn;

  bool get hasCopy => kind != PoderGlanceKind.missing;

  static const missing = PoderGlance();
}

/// OCR datum bez kopie není poder. Propadlý = kancelář nemá jednat.
PoderGlance poderGlanceOf({
  required bool hasCopy,
  String expiryRaw = '',
  required DateTime today,
  required int warnDays,
}) {
  if (!hasCopy) return PoderGlance.missing;
  final parsed = parseOfficeDate(expiryRaw);
  final tone = expiryTone(raw: expiryRaw, today: today, warnDays: warnDays);
  if (tone == ExpiryTone.expired) {
    return PoderGlance(kind: PoderGlanceKind.expired, expiresOn: parsed);
  }
  if (tone == ExpiryTone.expiring) {
    return PoderGlance(kind: PoderGlanceKind.expiring, expiresOn: parsed);
  }
  return PoderGlance(kind: PoderGlanceKind.present, expiresOn: parsed);
}

PoderGlance poderGlanceFromRpc({
  required Map raw,
  required DateTime today,
  required int warnDays,
}) {
  return poderGlanceOf(
    hasCopy: raw['has_copy'] == true,
    expiryRaw: '${raw['expiry_raw'] ?? ''}',
    today: today,
    warnDays: warnDays,
  );
}
