import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/carpeta/bloque_template.dart';
import 'package:gestoria_os/features/carpeta/carpeta_controller.dart';

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

  test('dvě koupě téhož klienta jsou různé desky', () {
    const a = CarpetaTarget(clienteId: 'c1', expedienteId: 'e1');
    const b = CarpetaTarget(clienteId: 'c1', expedienteId: 'e2');
    expect(a, isNot(b));
    expect(a.hashCode, isNot(b.hashCode));
  });
}
