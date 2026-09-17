import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/carpeta/bloque_template.dart';
import 'package:gestoria_os/features/carpeta/carpeta_controller.dart';
import 'package:gestoria_os/features/carpeta/carpeta_print.dart';

CarpetaPrintModel _model({
  required Map<String, BloqueState> bloques,
  List<BloqueTemplate>? templates,
  List<InmuebleTitular> titulares = const [],
  String nombre = 'Petr Sokol',
  String? direccion = 'Islandia 14',
}) {
  return buildCarpetaPrintModel(
    view: CarpetaView(
      clienteId: 'c1',
      tenantId: 't1',
      nombre: nombre,
      bloques: bloques,
      inmuebleDireccion: direccion,
      titulares: titulares,
    ),
    templates: templates ?? compraventaBloques,
    officeName: 'Gestorie Jarka',
    printedOn: '17-09-2026',
    bloqueLabel: (k) => k,
    fieldLabel: (k) => k,
    docLabel: (t) => t,
    statusLabel: (s) => s,
    sheet1Title: 'sheet1',
    sheet2Title: 'sheet2',
    printLabel: 'Print',
    offHeading: 'Off',
    titularesHeading: 'Titulares',
    docHave: 'have',
    docMissing: 'missing',
    ladoComprador: 'Comprador',
    ladoVendedor: 'Vendedor',
    nombreLabel: 'fields.nombre',
  );
}

void main() {
  test('neznámý blok jde na list 2', () {
    expect(carpetaPrintSheetFor('cliente_snapshot'), 1);
    expect(carpetaPrintSheetFor('suma'), 1);
    expect(carpetaPrintSheetFor('escritura'), 2);
    expect(carpetaPrintSheetFor('plusvalia'), 2);
    expect(carpetaPrintSheetFor('cizi_blok'), 2);
  });

  test('tisk jde časem papíru, ne pořadím šablon na desce', () {
    const snapshot = BloqueState(enabled: true, dbStatus: 'done');
    const agua = BloqueState(enabled: true, dbStatus: 'watching');
    const escritura = BloqueState(enabled: true, dbStatus: 'missing_document');
    final model = _model(
      bloques: {
        'cliente_snapshot': snapshot,
        'agua': agua,
        'escritura': escritura,
      },
      templates: const [
        BloqueTemplate(key: 'escritura', fieldKeys: ['fields.notary']),
        BloqueTemplate(key: 'agua', fieldKeys: ['fields.company']),
        BloqueTemplate(key: 'cliente_snapshot', fieldKeys: ['fields.nie']),
      ],
    );
    expect(model.sheet1.map((b) => b.key).toList(), [
      'cliente_snapshot',
      'agua',
    ]);
    expect(model.sheet2.map((b) => b.key).toList(), ['escritura']);
  });

  test('vypnutý blok je jen v Nesledujeme', () {
    final model = _model(
      bloques: {
        'cliente_snapshot': const BloqueState(enabled: true, dbStatus: 'done'),
        'luz': const BloqueState(enabled: false, dbStatus: 'off'),
        'escritura': const BloqueState(enabled: true, dbStatus: 'watching'),
      },
      templates: const [
        BloqueTemplate(key: 'cliente_snapshot', fieldKeys: ['fields.nie']),
        BloqueTemplate(key: 'luz', fieldKeys: ['fields.cups']),
        BloqueTemplate(key: 'escritura', fieldKeys: ['fields.notary']),
      ],
    );
    expect(model.offLabels, ['luz']);
    expect(model.sheet1.map((b) => b.key), ['cliente_snapshot']);
    expect(model.sheet2.map((b) => b.key), ['escritura']);
  });

  test('cents zálohy a chybějící papír jdou do HTML', () {
    final model = _model(
      bloques: {
        'provision_factura': const BloqueState(
          enabled: true,
          dbStatus: 'watching',
          values: {
            'fields.received': '1234',
            'fields.invoiced': '200',
            'fields.remaining': '1034',
          },
        ),
        'escritura': const BloqueState(
          enabled: true,
          dbStatus: 'missing_document',
          documents: [
            CarpetaDocumento(
              id: 'd1',
              tipo: 'nota_simple',
              storagePath: 't/c/x.pdf',
              originalName: 'x.pdf',
            ),
          ],
        ),
      },
      templates: const [
        BloqueTemplate(
          key: 'provision_factura',
          fieldKeys: [
            'fields.received',
            'fields.invoiced',
            'fields.remaining',
          ],
        ),
        BloqueTemplate(
          key: 'escritura',
          fieldKeys: ['fields.notary'],
          requiredDocTypes: ['copia_escritura'],
        ),
      ],
    );
    expect(model.sheet2.map((b) => b.key).toList(), [
      'escritura',
      'provision_factura',
    ]);
    final money = model.sheet2.firstWhere((b) => b.key == 'provision_factura');
    expect(money.fields.map((f) => f.value).toList(), [
      '12,34 €',
      '2,00 €',
      '10,34 €',
    ]);
    final escritura = model.sheet2.firstWhere((b) => b.key == 'escritura');
    expect(escritura.docs.single.have, isFalse);

    final html = carpetaPrintHtml(model);
    expect(html, contains('class="page"'));
    expect('class="page"'.allMatches(html).length, 2);
    expect(html, contains('12,34 €'));
    expect(html, contains('copia_escritura · missing'));
    expect(html, contains('Petr Sokol'));
    expect(html, contains('Gestorie Jarka'));
  });

  test('HTML escapuje jméno a titulares jdou na list 2', () {
    final model = _model(
      nombre: 'A <B> & "C"',
      bloques: {
        'cliente_snapshot': const BloqueState(
          enabled: true,
          dbStatus: 'done',
          values: {'fields.nie': 'Y1234567X'},
        ),
      },
      templates: const [
        BloqueTemplate(key: 'cliente_snapshot', fieldKeys: ['fields.nie']),
      ],
      titulares: const [
        InmuebleTitular(
          id: 't1',
          nombre: 'Monika <x>',
          nieRaw: 'X0000000T',
          lado: 'comprador',
          cuotaBps: 5000,
        ),
      ],
    );
    expect(model.titulares.single.share, '50.00 %');
    final html = carpetaPrintHtml(model);
    expect(html, isNot(contains('<B>')));
    expect(html, contains('A &lt;B&gt; &amp; &quot;C&quot;'));
    expect(html, contains('Monika &lt;x&gt;'));
    expect(html, contains('Comprador'));
    expect(html, contains('50.00 %'));
  });
}
