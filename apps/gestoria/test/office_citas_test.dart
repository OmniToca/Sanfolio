import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/citas/office_citas.dart';

void main() {
  test('kind z plazo a bloku, španělský papír ve výzvě', () {
    expect(citaKindOf(plazoKind: 'cita_nie', bloqueKey: 'nie_tramite'), 'nie');
    expect(
      citaKindOf(plazoKind: 'cita_tramite', bloqueKey: 'policia'),
      'policia',
    );
    expect(
      citaKindOf(plazoKind: 'cita_tramite', bloqueKey: 'ayuntamiento'),
      'ayuntamiento',
    );
    expect(
      citaKindOf(plazoKind: 'cita_tramite', bloqueKey: 'testament'),
      'testament',
    );
    expect(
      citaKindOf(plazoKind: 'escritura', bloqueKey: 'escritura'),
      'escritura',
    );
    expect(citaBloqueLabel('policia'), 'Policía');
    expect(citaBloqueLabel('escritura'), 'Escritura');
  });

  test('RPC bez klienta nebo data citou není', () {
    expect(officeCitaRowFromRpc({'bloque_key': 'policia'}), isNull);
    expect(
      officeCitaRowFromRpc({
        'cliente_id': 'c1',
        'bloque_key': 'policia',
        'plazo_kind': 'cita_tramite',
      }),
      isNull,
    );
  });

  test('řádek cit čte den a tenký spis, neodesílá', () {
    final row = officeCitaRowFromRpc({
      'cliente_id': 'c1',
      'cliente_nombre': 'Petr',
      'expediente_id': 'e1',
      'bloque_id': 'b1',
      'bloque_key': 'policia',
      'plazo_kind': 'cita_tramite',
      'due_on': '2026-09-17T00:00:00',
      'has_email': false,
      'has_tel': true,
    });
    expect(row?.kind, 'policia');
    expect(row?.dueOn, '2026-09-17');
    expect(row?.hasEmail, isFalse);
    expect(officeDayIso(officeDayToday(DateTime(2026, 9, 17))), '2026-09-17');
  });
}
