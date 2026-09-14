import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/time/office_date.dart';
import 'package:gestoria_os/features/expedientes/expediente_estado.dart';

void main() {
  test('OCR datum: ISO i španělské dd/mm, odpad není alert', () {
    expect(parseOfficeDate('2027-03-08'), DateTime(2027, 3, 8));
    expect(parseOfficeDate('01/03/2027'), DateTime(2027, 3, 1));
    expect(parseOfficeDate('XU'), isNull);
    expect(parseOfficeDate('32/13/2027'), isNull);
  });

  test('ISO datum z pole i z DateTime', () {
    expect(toIsoDate('14.9.2026'), '2026-09-14');
    expect(toIsoDate('14/09/2026'), '2026-09-14');
    expect(formatIsoDate(DateTime(2026, 9, 14)), '2026-09-14');
    expect(toIsoDate('XU'), isNull);
    expect(formatDmyDate(DateTime(2026, 9, 14)), '14-09-2026');
    expect(toDmyDate('2026-09-14'), '14-09-2026');
  });

  test('platnost bere dny z nastavení, ne hardcoded 30', () {
    final today = DateTime(2026, 9, 13);
    expect(
      expiryTone(raw: '2027-03-08', today: today, warnDays: 60),
      ExpiryTone.valid,
    );
    expect(
      expiryTone(raw: '2026-10-01', today: today, warnDays: 60),
      ExpiryTone.expiring,
    );
    expect(
      expiryTone(raw: '2026-01-01', today: today, warnDays: 60),
      ExpiryTone.expired,
    );
    expect(expiryTone(raw: 'XU', today: today, warnDays: 60), isNull);
  });

  test('pipeline má pět pracovních stavů, archiv je mimo řadu', () {
    expect(expedienteWorkingEstadoKeys, hasLength(5));
    expect(expedienteWorkingEstadoKeys, isNot(contains('archivado')));
    expect(expedienteEstadoKeys, contains('archivado'));
  });
}
