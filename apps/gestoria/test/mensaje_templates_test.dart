import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/mensajes/mensaje_templates.dart';

void main() {
  test('šablona doplní jméno a neodešle nic', () {
    final t = filledTemplate(
      key: 'falta_documento',
      vars: {
        'nombre': 'Ana',
        'documento': 'Contrato luz',
        'bloque': 'LUZ',
        'despacho': 'Gestorie TEST',
        'inmueble': 'Calle 1',
      },
    );
    expect(t.asunto, contains('Calle 1'));
    expect(t.cuerpo, contains('Ana'));
    expect(t.cuerpo, contains('Contrato luz'));
    expect(t.cuerpo, isNot(contains('{{nombre}}')));
  });

  test('inbox díra dokumentu bere šablonu falta_documento', () {
    expect(templateKeyForInboxKind('missing_document'), 'falta_documento');
    expect(templateKeyForInboxKind('overdue'), 'vencido');
    expect(templateKeyForBloqueStatus('missing_data'), 'faltan_datos');
  });
}
