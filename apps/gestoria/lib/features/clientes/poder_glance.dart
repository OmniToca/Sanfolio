import '../../core/time/office_date.dart';

/// Přehled plné moci. Pravda je kopie papíru, ne zapnutý blok desky.
enum PoderGlanceKind { missing, present, expiring, expired }

class PoderGlance {
  const PoderGlance({
    this.kind = PoderGlanceKind.missing,
    this.expiresOn,
    this.documentoId,
    this.storagePath,
    this.originalName,
  });

  final PoderGlanceKind kind;
  final DateTime? expiresOn;
  final String? documentoId;
  final String? storagePath;
  final String? originalName;

  bool get hasCopy => kind != PoderGlanceKind.missing;

  bool get canOpenSource {
    final path = storagePath?.trim() ?? '';
    return path.isNotEmpty || hasCopy;
  }

  static const missing = PoderGlance();
}

/// OCR datum bez kopie není poder. Propadlý = kancelář nemá jednat.
PoderGlance poderGlanceOf({
  required bool hasCopy,
  String expiryRaw = '',
  String? documentoId,
  String? storagePath,
  String? originalName,
  required DateTime today,
  required int warnDays,
}) {
  if (!hasCopy) return PoderGlance.missing;
  final parsed = parseOfficeDate(expiryRaw);
  final tone = expiryTone(raw: expiryRaw, today: today, warnDays: warnDays);
  final id = documentoId?.trim();
  final path = storagePath?.trim();
  final name = originalName?.trim();
  return PoderGlance(
    kind: switch (tone) {
      ExpiryTone.expired => PoderGlanceKind.expired,
      ExpiryTone.expiring => PoderGlanceKind.expiring,
      _ => PoderGlanceKind.present,
    },
    expiresOn: parsed,
    documentoId: (id == null || id.isEmpty) ? null : id,
    storagePath: (path == null || path.isEmpty) ? null : path,
    originalName: (name == null || name.isEmpty) ? null : name,
  );
}

PoderGlance poderGlanceFromRpc({
  required Map raw,
  required DateTime today,
  required int warnDays,
}) {
  return poderGlanceOf(
    hasCopy: raw['has_copy'] == true,
    expiryRaw: '${raw['expiry_raw'] ?? ''}',
    documentoId: '${raw['documento_id'] ?? ''}',
    storagePath: '${raw['storage_path'] ?? ''}',
    originalName: '${raw['original_name'] ?? ''}',
    today: today,
    warnDays: warnDays,
  );
}

/// Klíč čipu. Datum jde zvlášť, ať locale formátuje den.
String poderStampI18nKey(PoderGlance glance) {
  final dated = glance.expiresOn != null;
  return switch (glance.kind) {
    PoderGlanceKind.missing => 'clients.poderMissing',
    PoderGlanceKind.present =>
      dated ? 'clients.poderUntil' : 'clients.poder',
    PoderGlanceKind.expiring =>
      dated ? 'clients.poderExpiringUntil' : 'clients.poderExpiring',
    PoderGlanceKind.expired =>
      dated ? 'clients.poderExpiredUntil' : 'clients.poderExpired',
  };
}
