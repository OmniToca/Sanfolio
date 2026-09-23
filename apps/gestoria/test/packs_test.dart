import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/inbox/inbox_providers.dart';
import 'package:gestoria_os/features/mensajes/mensaje_templates.dart';
import 'package:gestoria_os/features/packs/office_pack_pedir.dart';
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
    expect(
      afterNotaryStillOpen(
        plusvaliaOpen: false,
        supplyHoles: const ['agua'],
        recentEscritura: true,
        tax210Needed: true,
        folderIsVendedor: true,
      ),
      isFalse,
    );
    expect(
      afterNotaryStillOpen(
        plusvaliaOpen: true,
        supplyHoles: const ['agua'],
        recentEscritura: true,
        tax210Needed: true,
        folderIsVendedor: true,
      ),
      isTrue,
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

  test('hromadný 210 bere falta_documento a přeskočí sin_canal', () {
    const row = Season210Row(
      clienteId: 'c1',
      clienteNombre: 'Ana',
      expedienteId: 'e1',
      bloqueId: 'b1',
      periodo: '2026-Q1',
      dueOn: '2026-04-20',
      missingDocs: ['recibo_ibi'],
    );
    final req = season210PedirRequest(
      row,
      channel: const ClienteChannel(hasEmail: false, hasTel: false),
      documentoLabel: 'Recibo IBI',
    );
    expect(req.templateKey, 'falta_documento');
    expect(req.bloqueKey, 'modelo_210');
    expect(req.fecha, '2026-04-20');
    expect(
      pedirSkipReason(req, nudgeIntervalDays: 7),
      PedirSkipReason.noChannel,
    );
  });

  test('hromadný po notáři je cambio_titular, ne odeslání', () {
    const row = AfterNotaryRow(
      clienteId: 'c1',
      clienteNombre: 'Petr',
      inmuebleId: 'i1',
      expedienteId: 'e1',
      direccion: 'Islandia 14',
      escrituraFecha: '2026-09-01',
      taxExpedienteId: 'tax1',
      tasks: ['plusvalia', 'agua'],
    );
    final stamp = BloqueStamp(
      id: 'b-agua',
      expedienteId: 'e1',
      templateKey: 'agua',
    );
    final req = afterNotaryPedirRequest(
      row,
      channel: const ClienteChannel(hasEmail: true, hasTel: false),
      stamp: stampForNotary(row, [stamp]),
    );
    expect(req.templateKey, 'cambio_titular');
    expect(req.bloqueKey, 'agua');
    expect(req.bloqueId, 'b-agua');
    expect(req.inmueble, 'Islandia 14');
    expect(pedirSkipReason(req, nudgeIntervalDays: 7), isNull);
  });

  test('IBI do kampaně jen se splatností a dírou nebo oknem', () {
    expect(
      seasonIbiOpen(
        bloqueStatus: 'missing_document',
        dueConfigured: true,
        inWarnWindow: false,
        missingRecibo: true,
      ),
      isTrue,
    );
    expect(
      seasonIbiOpen(
        bloqueStatus: 'watching',
        dueConfigured: true,
        inWarnWindow: true,
        missingRecibo: false,
      ),
      isTrue,
    );
    expect(
      seasonIbiOpen(
        bloqueStatus: 'missing_document',
        dueConfigured: false,
        inWarnWindow: true,
        missingRecibo: true,
      ),
      isFalse,
    );
    expect(
      seasonIbiOpen(
        bloqueStatus: 'done',
        dueConfigured: true,
        inWarnWindow: true,
        missingRecibo: true,
      ),
      isFalse,
    );
  });

  test('hromadný IBI je suma, ne modelo_210', () {
    const row = Season210Row(
      clienteId: 'c1',
      clienteNombre: 'Ana',
      expedienteId: 'e1',
      bloqueId: 'b1',
      periodo: '2026',
      dueOn: '2026-11-01',
      missingDocs: ['recibo_ibi'],
    );
    final req = seasonIbiPedirRequest(
      row,
      channel: const ClienteChannel(hasEmail: true, hasTel: false),
      documentoLabel: 'Recibo IBI',
    );
    expect(req.templateKey, 'falta_documento');
    expect(req.bloqueKey, 'suma');
    expect(req.fecha, '2026-11-01');
    expect(pedirSkipReason(req, nudgeIntervalDays: 7), isNull);
  });
}
