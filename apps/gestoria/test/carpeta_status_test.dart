import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/carpeta/bloque_template.dart';
import 'package:gestoria_os/features/carpeta/carpeta_controller.dart';
import 'package:gestoria_os/features/carpeta/carpeta_screen.dart';

void main() {
  test('zapnutý cliente_snapshot bez NIE je done — jméno žije na clientes', () {
    const template = BloqueTemplate(
      key: 'cliente_snapshot',
      fieldKeys: ['fields.nie', 'fields.email'],
      requiredFieldKeys: [],
    );
    const state = BloqueState(enabled: true);
    expect(statusOf(template, state), BloqueUiStatus.done);
  });

  test('zapnutá escritura bez kopie je missing_document', () {
    const template = BloqueTemplate(
      key: 'escritura',
      fieldKeys: ['fields.notary'],
      requiredFieldKeys: [],
      requiredDocTypes: ['copia_escritura'],
    );
    const state = BloqueState(enabled: true);
    expect(statusOf(template, state), BloqueUiStatus.missingDocument);
  });

  test('voda s fakturou bez smlouvy není díra dokumentu', () {
    const template = BloqueTemplate(
      key: 'agua',
      fieldKeys: [
        'fields.company',
        'fields.clientNo',
        'fields.contractNo',
        'fields.holder',
      ],
      requiredFieldKeys: [
        'fields.company',
        'fields.clientNo',
        'fields.holder',
      ],
      requiredDocTypes: ['contrato_agua', 'factura_agua'],
      requiredDocsMode: RequiredDocsMode.any,
    );
    const state = BloqueState(
      enabled: true,
      values: {
        'fields.company': 'Hidraqua',
        'fields.clientNo': '123',
        'fields.holder': 'Petr Sokol',
      },
      documents: [
        CarpetaDocumento(
          id: 'd1',
          tipo: 'factura_agua',
          storagePath: 't/c/f.pdf',
          originalName: 'factura.pdf',
        ),
      ],
    );
    expect(statusOf(template, state), BloqueUiStatus.done);
  });

  test('vypnutý blok je off', () {
    const template = BloqueTemplate(key: 'luz', fieldKeys: ['fields.cups']);
    const state = BloqueState(enabled: false);
    expect(statusOf(template, state), BloqueUiStatus.off);
  });

  test('modelo 210 bez papírů je missing_document, ne daňový výpočet', () {
    const template = BloqueTemplate(
      key: 'modelo_210',
      fieldKeys: ['fields.periodicity', 'fields.modeloPeriod', 'fields.deadline'],
      requiredDocTypes: [
        'escritura_o_nota_simple',
        'recibo_ibi',
        'certificado_catastral',
      ],
    );
    const state = BloqueState(
      enabled: true,
      values: {
        'fields.periodicity': 'trimestral',
        'fields.modeloPeriod': '2026-Q1',
        'fields.deadline': '2026-04-20',
      },
    );
    expect(statusOf(template, state), BloqueUiStatus.missingDocument);
  });

  test('chip bere watching z DB, ne z Flutter odhadu', () {
    expect(bloqueUiStatus('watching'), BloqueUiStatus.watching);
    expect(bloqueUiStatus('off'), BloqueUiStatus.off);
    expect(bloqueUiStatus('done'), BloqueUiStatus.done);
  });

  test('persist jen chip — hodnoty z tužky se nesmí vyměnit za starý snímek', () {
    const live = BloqueState(
      enabled: true,
      values: {'fields.address': 'Calle Isla'},
      dbStatus: 'missing_data',
    );
    const stale = BloqueState(
      enabled: true,
      values: {'fields.address': ''},
      dbStatus: 'missing_data',
    );
    final applied = live.copyWith(dbStatus: 'watching');
    expect(applied.values['fields.address'], 'Calle Isla');
    expect(applied.dbStatus, 'watching');
    expect(stale.copyWith(dbStatus: 'watching').values['fields.address'], isEmpty);
  });

  test('dvě koupě téhož klienta jsou různé desky', () {
    const a = CarpetaTarget(clienteId: 'c1', expedienteId: 'e1');
    const b = CarpetaTarget(clienteId: 'c1', expedienteId: 'e2');
    expect(a, isNot(b));
    expect(a.hashCode, isNot(b.hashCode));
  });

  test('políčko ukáže eura, ne surové cents — jinak sync smaže rozepsaný text', () {
    expect(displayBloqueField('fields.address', 'Calle Isla'), 'Calle Isla');
    expect(displayBloqueField('fields.received', '100'), '1,00');
    expect(displayBloqueField('fields.invoiced', ''), '');
  });
}
