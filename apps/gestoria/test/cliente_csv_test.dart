import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/clientes/cliente_csv.dart';

void main() {
  test('středník a čárka, jméno je povinné', () {
    final semi = parseClienteCsv(
      'nombre;nie;email\n'
      'Ana Pérez;Y1234567Z;ana@x.es\n'
      ';X0000000T;\n',
    );
    expect(semi.error, isNull);
    expect(semi.readyCount, 1);
    expect(semi.emptyCount, 1);
    expect(semi.rows.first.nombre, 'Ana Pérez');
    expect(semi.rows.first.nie, 'Y1234567Z');

    final comma = parseClienteCsv(
      'name,dni,mail\n'
      'Petr,12345678Z,p@x.cz\n',
    );
    expect(comma.readyCount, 1);
    expect(comma.rows.first.nombre, 'Petr');
    expect(comma.rows.first.nie, '12345678Z');
  });

  test('existující NIE a duplicita v souboru se přeskočí', () {
    final parsed = parseClienteCsv(
      'nombre;nie\n'
      'Ana;Y1234567Z\n'
      'Petr;Y1234567Z\n'
      'Monika;X1111111A\n',
      liveNies: const ['Y1234567Z'],
    );
    expect(parsed.rows[0].status, ClienteCsvStatus.skipDuplicate);
    expect(parsed.rows[1].status, ClienteCsvStatus.skipDuplicate);
    expect(parsed.rows[2].status, ClienteCsvStatus.ready);
  });

  test('uvozovky schovají středník, locale jen cs/en/es/de/fr', () {
    final parsed = parseClienteCsv(
      'nombre;direccion;locale\n'
      '"Pérez; Ana";Calle 1;CS\n'
      'Petr;Calle 2;it\n',
    );
    expect(parsed.rows.first.nombre, 'Pérez; Ana');
    expect(parsed.rows.first.direccion, 'Calle 1');
    expect(parsed.rows.first.locale, 'cs');
    expect(parsed.rows[1].locale, '');
  });

  test('bez sloupce nombre a nad limit', () {
    expect(parseClienteCsv('nie;email\nY1;a@b.cz').error, 'header');
    expect(parseClienteCsv('').error, 'empty');
    final buf = StringBuffer('nombre\n');
    for (var i = 0; i < clienteCsvMaxRows + 3; i++) {
      buf.writeln('Klient $i');
    }
    final parsed = parseClienteCsv(buf.toString());
    expect(parsed.error, 'tooMany');
    expect(parsed.rows.length, clienteCsvMaxRows);
  });

  test('dávka RPC skládá po 40 a sčítá výsledek', () {
    final payload = clienteCsvReadyPayload([
      for (var i = 0; i < 41; i++)
        ClienteCsvDraft(
          line: i + 2,
          nombre: 'K$i',
          nie: '',
          email: '',
          tel: '',
          direccion: '',
          locale: '',
          status: ClienteCsvStatus.ready,
        ),
    ]);
    final chunks = chunkClienteCsvPayload(payload);
    expect(chunks.length, 2);
    expect(chunks.first.length, 40);
    expect(chunks.last.length, 1);
    final a = clienteCsvImportResultFromRpc({
      'created': 40,
      'skipped_empty': 0,
      'skipped_duplicate': 1,
      'errors': [
        {'row': 2},
      ],
    });
    final b = clienteCsvImportResultFromRpc({'created': 1});
    final sum = a + b;
    expect(sum.created, 41);
    expect(sum.skippedDuplicate, 1);
    expect(sum.errors, 1);
  });
}
