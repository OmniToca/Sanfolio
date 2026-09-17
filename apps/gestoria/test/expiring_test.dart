import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/packs/expiring_campaign.dart';

void main() {
  test('kampaň bere stejné okno jako chip na kartě', () {
    final today = DateTime(2026, 9, 17);
    expect(
      expiringInCampaign(raw: '2026-10-01', today: today, warnDays: 60),
      isTrue,
    );
    expect(
      expiringInCampaign(raw: '2026-01-01', today: today, warnDays: 60),
      isTrue,
    );
    expect(
      expiringInCampaign(raw: '2027-03-08', today: today, warnDays: 60),
      isFalse,
    );
    expect(
      expiringInCampaign(raw: 'XU', today: today, warnDays: 60),
      isFalse,
    );
    expect(
      expiringInCampaign(raw: '2026-10-01', today: today, warnDays: 0),
      isFalse,
    );
  });

  test('poder bere dny poder, seguro svoje', () {
    expect(warnDaysForExpiringKind('poder', poder: 45, seguro: 90), 45);
    expect(warnDaysForExpiringKind('dni_nie', poder: 45, seguro: 90), 45);
    expect(warnDaysForExpiringKind('seguro', poder: 45, seguro: 90), 90);
  });

  test('DNI je core, poder a seguro jdou za modulem', () {
    expect(
      expiringKindVisible('dni_nie', niePoderOn: false, carpetaOn: false),
      isTrue,
    );
    expect(
      expiringKindVisible('poder', niePoderOn: false, carpetaOn: true),
      isFalse,
    );
    expect(
      expiringKindVisible('seguro', niePoderOn: true, carpetaOn: false),
      isFalse,
    );
    expect(
      expiringKindVisible('seguro', niePoderOn: false, carpetaOn: true),
      isTrue,
    );
  });

  test('prošlý DNI je vencido, ne odeslání', () {
    final row = expiringRowFromRpc({
      'cliente_id': 'c1',
      'cliente_nombre': 'Ana',
      'kind': 'dni_nie',
      'expires_on': '2026-01-15',
      'tone': 'expired',
      'has_email': true,
      'has_tel': false,
    });
    expect(row?.isExpired, isTrue);
    final req = expiringPedirRequest(row!);
    expect(req.templateKey, 'vencido');
    expect(req.bloqueKey, 'DNI / NIE');
    expect(req.bloqueId, isNull);
    expect(req.fecha, '2026-01-15');
  });

  test('brzy končící poder razítkuje blok', () {
    final row = expiringRowFromRpc({
      'cliente_id': 'c1',
      'cliente_nombre': 'Petr',
      'kind': 'poder',
      'expires_on': '2026-10-01T00:00:00',
      'tone': 'expiring',
      'bloque_id': 'b-poder',
      'expediente_id': 'e1',
      'last_requested_at': '2026-09-01T10:00:00Z',
    });
    expect(row?.expiresOn, '2026-10-01');
    final req = expiringPedirRequest(row!);
    expect(req.templateKey, 'recordatorio');
    expect(req.bloqueId, 'b-poder');
    expect(req.lastRequestedAt, isNotNull);
    expect(expiringRowFromRpc({'cliente_id': 'c1', 'kind': 'alarma'}), isNull);
  });
}
