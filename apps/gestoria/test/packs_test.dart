import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/mensajes/mensaje_templates.dart';
import 'package:gestoria_os/features/packs/office_packs.dart';

void main() {
  test('sezóna 210 bere jen otevřený spis bez podání', () {
    expect(
      season210Open(
        bloqueStatus: 'missing_document',
        expedienteEstado: 'en_curso',
        filed: '',
      ),
      isTrue,
    );
    expect(
      season210Open(
        bloqueStatus: 'watching',
        expedienteEstado: 'en_curso',
        filed: '2026-04-01',
      ),
      isFalse,
    );
    expect(
      season210Open(
        bloqueStatus: 'done',
        expedienteEstado: 'hecho',
        filed: '',
      ),
      isFalse,
    );
  });

  test('po notáři zbývá práce, ne celá kancelář', () {
    expect(
      afterNotaryStillOpen(
        plusvaliaOpen: true,
        supplyHoles: const [],
        recentEscritura: false,
        tax210Needed: false,
      ),
      isTrue,
    );
    expect(
      afterNotaryStillOpen(
        plusvaliaOpen: false,
        supplyHoles: const ['agua'],
        recentEscritura: true,
        tax210Needed: true,
      ),
      isTrue,
    );
    expect(
      afterNotaryStillOpen(
        plusvaliaOpen: false,
        supplyHoles: const [],
        recentEscritura: false,
        tax210Needed: true,
      ),
      isFalse,
    );
  });

  test('Nachystat cambio de titular je šablona compose, ne odeslání', () {
    expect(mensajeTemplateByKey('cambio_titular')?.key, 'cambio_titular');
    expect(draftTemplateForNotary(const ['agua', 'plusvalia']), 'cambio_titular');
    expect(draftBloqueForNotary(const ['agua', 'plusvalia']), 'agua');
    expect(draftTemplateForNotary(const ['plusvalia']), 'recordatorio');
    expect(draftBloqueForNotary(const ['modelo_210']), 'modelo_210');
    final row = afterNotaryRowFromRpc({
      'cliente_id': 'c1',
      'cliente_nombre': 'Petr',
      'inmueble_id': 'i1',
      'expediente_id': 'e1',
      'escritura_fecha': '2026-09-01',
      'tasks': ['plusvalia', 'agua'],
    });
    expect(row?.tasks, ['plusvalia', 'agua']);
    expect(season210RowFromRpc({'cliente_id': 'c1'}), isNull);
  });
}
