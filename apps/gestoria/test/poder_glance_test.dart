import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/clientes/poder_glance.dart';

void main() {
  final today = DateTime(2026, 9, 23);

  test('bez kopie není poder, i když deska má datum', () {
    expect(
      poderGlanceOf(
        hasCopy: false,
        expiryRaw: '2027-01-01',
        today: today,
        warnDays: 60,
      ).kind,
      PoderGlanceKind.missing,
    );
  });

  test('kopie bez data je poder', () {
    expect(
      poderGlanceOf(
        hasCopy: true,
        today: today,
        warnDays: 60,
      ).kind,
      PoderGlanceKind.present,
    );
  });

  test('kopie v okně končí, po datu propadlá', () {
    expect(
      poderGlanceOf(
        hasCopy: true,
        expiryRaw: '2026-10-01',
        today: today,
        warnDays: 60,
      ).kind,
      PoderGlanceKind.expiring,
    );
    expect(
      poderGlanceOf(
        hasCopy: true,
        expiryRaw: '2026-01-01',
        today: today,
        warnDays: 60,
      ).kind,
      PoderGlanceKind.expired,
    );
  });

  test('RPC řádek se čte stejně', () {
    final g = poderGlanceFromRpc(
      raw: {'has_copy': true, 'expiry_raw': '2028-03-01'},
      today: today,
      warnDays: 60,
    );
    expect(g.kind, PoderGlanceKind.present);
  });
}
