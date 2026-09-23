import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/ai/documento_fields.dart';
import 'package:gestoria_os/features/ai/escritura_parties.dart';
import 'package:gestoria_os/features/ai/extract_text.dart';
import 'package:gestoria_os/features/ai/paper_glance.dart';
import 'package:gestoria_os/features/carpeta/bloque_template.dart';
import 'package:gestoria_os/features/carpeta/carpeta_routes.dart';
import 'package:gestoria_os/features/expedientes/expediente_catalog.dart';

void main() {
  test('extract najde NIE, e-mail a tel, nic neukládá', () {
    final out = extractFromText(
      'Cliente ANA, NIE Y1234567E, mail ana@test.com, tel +34 612 345 678',
    );
    expect(out.nie, 'Y1234567E');
    expect(out.email, 'ana@test.com');
    expect(out.tel, '+34612345678');
  });

  test('CTA bancaria je IBAN, ne telefon z číslic za ES', () {
    const sheet = '''
NOMBRE DE LA CUENTA/ACCOUNT NAME: LA MARINA SERVICES INTERNATIONAL
IBAN: ES96 2100 9143 9413 0049 8086
BIC: CAIXESBBXXX
''';
    final out = extractFromText(sheet);
    expect(out.iban, 'ES9621009143941300498086');
    expect(out.tel, isNull);
    expect(
      sanitizeExtractedFields({
        'fields.iban': 'ES96 2100 9143 9413 0049 8086',
        'fields.tel': '9621009143941',
      }),
      {'fields.iban': 'ES9621009143941300498086'},
    );
    expect(looksLikeIban('ES0021000012345678AB'), isFalse);
    expect(looksLikeTel('9621009143941'), isFalse);
    expect(looksLikeTel('612345678'), isTrue);
    expect(extractFromText('Factura nº 612345678 Importe 88,50').tel, isNull);
    expect(
      displayDocumentoFields(
        fields: {'fields.tel': '9621009143941'},
        bodyText: sheet,
      ),
      {'fields.iban': 'ES9621009143941300498086'},
    );
    expect(
      formatIban('ES9621009143941300498086'),
      'ES96 2100 9143 9413 0049 8086',
    );
  });

  test('jiný layout banky (Revolut) pořád najde IBAN, ne Tel z číslic', () {
    const sheet = '''
Euro
Beneficiary
Renata Susicova
IBAN
ES10 1583 0001 1190 1063 9767
BIC/SWIFT code
REVOESM2
''';
    final out = extractFromText(sheet);
    expect(out.iban, 'ES1015830001119010639767');
    expect(out.tel, isNull);
  });

  test('žlutý diff ukáže změnu a prázdné teď, nic neukládá', () {
    final diffs = prefillDiffs(
      current: {'fields.nie': '', 'fields.email': 'old@test.com'},
      proposed: {
        'fields.nie': 'Y1234567E',
        'fields.email': 'old@test.com',
        'fields.tel': '+34612345678',
      },
    );
    expect(diffs.length, 3);
    expect(diffs.first.changed, isTrue);
    expect(diffs[1].changed, isFalse);
    expect(stringFieldMap({'fields.nie': 'Y1234567E', 'skip': ''}), {
      'fields.nie': 'Y1234567E',
    });
  });

  test('odpad z PDF se nenabízí místo platného NIE', () {
    expect(looksLikeNie('XU'), isFalse);
    expect(looksLikeNie('Y9736943E'), isTrue);
    expect(looksLikeTel('0000000000278' * 8), isFalse);
    expect(looksLikeTel('+420775869555'), isTrue);
    expect(
      sanitizeExtractedFields({
        'fields.nie': 'XU',
        'fields.tel': '278000000000333330027833327827856556556556556556',
      }),
      isEmpty,
    );
    final diffs = prefillDiffs(
      current: {'fields.nie': 'Y9736943E', 'fields.tel': '+420775869555'},
      proposed: {'fields.nie': 'XU', 'fields.tel': '0000000000278'},
    );
    expect(diffs, isEmpty);
  });

  test('jméno na pase pozná stejného člověka', () {
    expect(namesLikelyMatch('Petr Sokol', 'SOKOL, PETR'), isTrue);
    expect(namesLikelyMatch('Petr Sokol', 'Ana García'), isFalse);
    expect(namesLikelyMatch('Petr Sokol', 'Petr Novak'), isFalse);
    expect(namesLikelyMatch('Petr Sokol', ''), isFalse);
    expect(namesLikelyMatch('Petr Sokol', 'PETR SOKOL Y MONIKA'), isTrue);
  });

  test('NIE na kartě se nepřepíše cizím číslem ani stejným křestním', () {
    expect(
      nieMayReplaceCard(cardNie: 'Y9736943E', paperNie: 'Y9737090P'),
      isFalse,
    );
    expect(
      nieMayReplaceCard(cardNie: 'Y9736943E', paperNie: 'Y-9736943-E'),
      isTrue,
    );
    expect(nieMayReplaceCard(cardNie: '', paperNie: 'Y9737090P'), isTrue);
    expect(nieMayReplaceCard(cardNie: 'Y9736943E', paperNie: ''), isTrue);
    expect(
      documentFitsCliente(
        cardName: 'Petr Sokol',
        cardNie: 'Y9736943E',
        fields: {'fields.nombre': 'Petr Sokol', 'fields.nie': 'Y9737090P'},
      ),
      isFalse,
    );
    expect(
      documentFitsCliente(
        cardName: 'Petr Sokol',
        cardNie: 'Y9736943E',
        fields: {'fields.nombre': 'Petr Sokol', 'fields.docNumber': '43927578'},
      ),
      isTrue,
    );
    final locked = lockIdentityPaper(
      paper: const {
        'fields.nie': 'Y9737090P',
        'fields.email': 'monika@test.com',
        'fields.notary': 'López',
      },
      cardName: 'Petr Sokol',
      cardNie: 'Y9736943E',
    );
    expect(locked.containsKey('fields.nie'), isFalse);
    expect(locked.containsKey('fields.email'), isFalse);
    expect(locked['fields.notary'], 'López');
    expect(
      applyExtractNotice(mismatch: true, skippedDeedParties: false),
      'folder.applyMismatch',
    );
    expect(
      applyExtractNotice(mismatch: true, skippedDeedParties: true),
      'folder.deedPartiesSkipped',
    );
  });

  test('facturas-5.pdf je factura_agua, ne první díra contrato', () {
    expect(
      guessDocumentoTipo(
        requiredDocTypes: const ['contrato_agua', 'factura_agua'],
        alreadyHave: {},
        originalName: 'facturas-5.pdf',
      ),
      'factura_agua',
    );
    expect(
      guessDocumentoTipo(
        requiredDocTypes: const ['contrato_luz', 'factura_luz'],
        alreadyHave: {},
        originalName: '31_07_2026.pdf',
      ),
      'factura_luz',
    );
    expect(
      guessDocumentoTipo(
        requiredDocTypes: const ['contrato_luz', 'factura_luz'],
        alreadyHave: {},
        originalName: 'contrato_iberdrola.pdf',
      ),
      'contrato_luz',
    );
  });

  test('Guardar faktury nepřeje částku na desku elektřiny', () {
    final desk = promotePaperToDesk(
      deskFieldKeys: const [
        'fields.company',
        'fields.cups',
        'fields.contractNo',
        'fields.holder',
      ],
      desk: const {'fields.cups': 'ES 0021'},
      paper: const {
        'fields.contractNo': '810921765',
        'fields.amount': '188.85',
        'fields.periodFrom': '2026-06-26',
      },
    );
    expect(desk['fields.contractNo'], '810921765');
    expect(desk['fields.cups'], 'ES 0021');
    expect(desk.containsKey('fields.amount'), isFalse);
  });

  test('Guardar IBI doplní rok SUMA, ne číslo účtenky', () {
    final paper = alignSumaPaperToDesk({
      'fields.invoiceNo': '0133875',
      'fields.periodFrom': '2024-01-01',
      'fields.periodTo': '2024-12-31',
      'fields.issued': '2024-02-02',
      'fields.amount': '76.78',
      'fields.cadastral': '4244203YH0244S0003RX',
      'fields.concept': 'Aplazamiento/Fraccionamiento de deuda',
    });
    expect(paper['fields.period'], '2024');
    expect(paper['fields.directDebit'], 'false');
    expect(paper.containsKey('fields.sumaId'), isFalse);
    final desk = promotePaperToDesk(
      deskFieldKeys: const [
        'fields.sumaId',
        'fields.directDebit',
        'fields.period',
      ],
      desk: const {},
      paper: paper,
    );
    expect(desk['fields.period'], '2024');
    expect(desk['fields.directDebit'], 'false');
    expect(desk.containsKey('fields.sumaId'), isFalse);
    expect(desk.containsKey('fields.invoiceNo'), isFalse);
  });

  test('číselné nº cliente na IBI je identifikace SUMA', () {
    final paper = alignSumaPaperToDesk({
      'fields.clientNo': '6949519',
      'fields.issued': '2025-08-20',
      'fields.concept': 'IBI domiciliado',
    });
    expect(paper['fields.sumaId'], '6949519');
    expect(paper['fields.period'], '2025');
    expect(paper['fields.directDebit'], 'true');
  });

  test('IBI pohled neshazuje protokol z listiny', () {
    expect(
      extraPaperFieldKeys({
        'fields.protocol': '2116',
        'fields.nie': 'Y9908856X',
        'fields.cadastral': '4244203YH0244S0003RX',
        'fields.address': 'AV SAN FULGENCIO-MARINA 3',
        'fields.amount': '76.78',
      }, tipo: 'recibo_ibi'),
      ['fields.cadastral', 'fields.address'],
    );
  });

  test('stoh faktur sečte kladné částky a dobropis vynechá', () {
    final glance = stackGlanceOf([
      (
        tipo: 'factura_luz',
        fields: {'fields.amount': '188.85', 'fields.periodTo': '2026-07-23'},
      ),
      (
        tipo: 'factura_luz',
        fields: {'fields.amount': '179.87', 'fields.periodTo': '2026-06-23'},
      ),
      (
        tipo: 'factura_luz',
        fields: {'fields.amount': '-20.00', 'fields.periodTo': '2026-06-01'},
      ),
      (tipo: 'contrato_luz', fields: {'fields.contractNo': '810921765'}),
    ]);
    expect(glance.invoiceCount, 3);
    expect(glance.paidCents, 18885 + 17987);
    expect(glance.latest?.amountCents, 18885);
    expect(glance.bars, [17987, 18885]);
  });

  test('efektivní cena z kWh a roční odhad z období faktury', () {
    final glance = stackGlanceOf([
      (
        tipo: 'factura_luz',
        fields: {
          'fields.amount': '188.85',
          'fields.consumption': '1120 kWh',
          'fields.periodFrom': '2026-06-26',
          'fields.periodTo': '2026-07-23',
        },
      ),
    ]);
    expect(glance.effectiveUnitCents, 17);
    expect(glance.annualCentsEstimate, isNotNull);
    expect(glance.yearlyConsumption, greaterThan(1000));
    // Elektřina zůstává u skutečných dní, ne u kvartálu vody.
    expect(periodDaysOf(glance.latest!), 27);
  });

  test('voda s měsícem z grafu se anualizuje jako španělský kvartál', () {
    final glance = stackGlanceOf([
      (
        tipo: 'factura_agua',
        fields: {
          'fields.amount': '122.48',
          'fields.consumption': '38 m³',
          'fields.periodFrom': '2026-02-01',
          'fields.periodTo': '2026-02-28',
        },
      ),
    ]);
    expect(periodDaysOf(glance.latest!), kAguaQuarterDays);
    expect(
      glance.annualCentsEstimate,
      (12248 * 365 / kAguaQuarterDays).round(),
    );
    expect(glance.annualCentsEstimate, lessThan(60000));
    final trueQuarter = stackGlanceOf([
      (
        tipo: 'factura_agua',
        fields: {
          'fields.amount': '122.48',
          'fields.periodFrom': '2025-11-21',
          'fields.periodTo': '2026-02-20',
        },
      ),
    ]);
    expect(periodDaysOf(trueQuarter.latest!), 91);
  });

  test('póliza nese prémii, smlouva bez částky ne', () {
    expect(fieldsForDocTipo('poliza_seguro'), contains('fields.amount'));
    final glance = stackGlanceOf([
      (
        tipo: 'poliza_seguro',
        fields: {'fields.amount': '420.00', 'fields.company': 'Mapfre'},
      ),
    ]);
    expect(glance.invoiceCount, 0);
    expect(glance.policyPremiumCents, 42000);
    expect(parseConsumptionQty('12,5 m³'), 12.5);
  });

  test('stoh faktur řadí od nejnovějšího období', () {
    expect(isInvoiceDocTipo('factura_agua'), isTrue);
    expect(isInvoiceDocTipo('factura_recibida'), isTrue);
    expect(isInvoiceDocTipo('contrato_agua'), isFalse);
    expect(
      paperSortStamp({
        'fields.periodTo': '2024-09-30',
        'fields.issued': '2024-09-23',
      }),
      '2024-09-30',
    );
  });

  test('uložený OCR není pod fakturou, když už jsou pole', () {
    expect(
      showDocumentoBodyOnPaper(
        hasShownFields: true,
        bodyText: '--- Strana 1/4 ---\nFACTURA DE ELECTRICIDAD',
      ),
      isFalse,
    );
    expect(
      showDocumentoBodyOnPaper(
        hasShownFields: false,
        bodyText: '--- Strana 1 ---\nContrato',
      ),
      isTrue,
    );
    expect(
      showDocumentoBodyOnPaper(hasShownFields: false, bodyText: '  '),
      isFalse,
    );
  });

  test('pending extract se neuloží jako pole desky', () {
    expect(isExtractPending({kExtractStatus: 'pending'}), isTrue);
    expect(isExtractFailed({kExtractStatus: 'failed'}), isTrue);
    final t = splitDocumentoTranscript({
      'extract_status': 'pending',
      'fields.company': 'Iberdrola',
    });
    expect(t.fields.containsKey('extract_status'), isFalse);
    expect(t.fields['fields.company'], 'Iberdrola');
    expect(documentTextSearchQueryOk('ar'), isFalse);
    expect(documentTextSearchQueryOk('arras'), isTrue);
  });

  test('policie je tenký spis, ne druhá carpeta', () {
    expect(thinKindByTipo('policia')?.moduleKey, 'policia');
    expect(thinKindByTipo('ayuntamiento')?.templateKey, 'ayuntamiento');
    expect(thinKindByTipo('testament')?.requiredDocsMode, RequiredDocsMode.any);
  });

  test('modelo 210 má desku nemovitosti, sloty papírů a výpočet IRNR', () {
    final kind = thinKindByTipo('impuestos_210')!;
    expect(kind.linksInmueble, isTrue);
    expect(
      kind.fieldKeys,
      containsAll(['fields.cadastral', 'fields.notes', 'fields.incomeKind']),
    );
    expect(
      kind.requiredFieldKeys,
      containsAll(['fields.incomeKind', 'fields.taxResidency']),
    );
    expect(kind.requiredFieldKeys, isNot(contains('fields.cadastral')));
    expect(
      kind.paperSlotTypes,
      containsAll([
        'escritura_o_nota_simple',
        'recibo_ibi',
        'certificado_catastral',
        'dni_nie',
      ]),
    );
    expect(kind.requiredDocTypes, isNot(contains('dni_nie')));
    expect(thinKindByTipo('impuestos_renta')!.linksInmueble, isFalse);
    expect(thinKindByTipo('policia')!.fieldKeys, contains('fields.authority'));
    expect(thinKindByTipo('ayuntamiento')!.linksInmueble, isTrue);
  });

  test('klient zůstane na deskách, voda se otevírá', () {
    expect(
      compraventaBloques
          .firstWhere((b) => b.key == 'cliente_snapshot')
          .opensFromDesk,
      isFalse,
    );
    expect(
      compraventaBloques.firstWhere((b) => b.key == 'agua').opensFromDesk,
      isTrue,
    );
    expect(
      carpetaBloqueRoute('c1', 'agua', expedienteId: 'e1'),
      '/clientes/c1/carpeta/agua?exp=e1',
    );
  });

  test('smlouva_spanelsko.pdf je copia_escritura i na kartě klienta', () {
    expect(
      guessDocumentoTipo(
        requiredDocTypes: const [],
        alreadyHave: {},
        originalName: 'smlouva_spanelsko.pdf',
      ),
      'copia_escritura',
    );
    expect(
      guessDocumentoTipo(
        requiredDocTypes: const ['copia_escritura'],
        alreadyHave: {},
        originalName: 'escritura_compraventa.pdf',
      ),
      'copia_escritura',
    );
  });

  test('compraventa pozná kupujícího za zmocněncem, ne prodávající', () {
    const deed = '''
COMPRAVENTA
NUMERO DOS MIL CIENTO DIECISÉIS.
En Almoradí, a veintinueve de Julio de dos mil veintidós.
Ante mí, LUÍS LORENZO SERRA, Notario del Ilustre Colegio de Valencia,
COMPARECEN:
DE UNA PARTE Y PARA VENDER:
Dª PATRICIA FRANCIS DAVIDSON, de soltera AYRES, nacida el día 16 de Marzo de 1955,
con pasaporte número 557432941, y con N.I.E. número X-7183596-Y.
Y DE OTRA, PARA COMPRAR:
Dª SOPHIE ELIZABETH RODRIGUEZ FITZ-HENLEY, nacida el día 30 de Septiembre de 1983,
con N.I.E. número X-8764216-C.
Y EN SU CONDICIÓN DE INTÉRPRETE:
Dª ABBIGAIL DAPHNE BARRATT, nacida el día 21 de Julio de 1992, con N.I.E. número X-9922948-N.
INTERVIENEN: A) La Sra. Rodríguez Fitz-Henry interviene en nombre y representación
de los cónyuges D. PETR SOKOL, nacido el día 5 de Junio de 1987, y Dª MONIKA SOKOLOVA,
nacida el día 16 de Abril de 1985, con N.I.E. números Y-9736943-E e Y-9737090-P,
respectivamente.
EXPONEN:
URBANA.- Vivienda en término de Algorfa, de la parcela R-2.2, hoy calle Islandia, número catorce.
INSCRIPCIÓN.- En el Registro de la Propiedad de Torrevieja Número Uno, finca número 4.297.
REFERENCIA CATASTRAL. - 8443304XH9184S0025KY, según manifiestan.
OTORGAN:
Es precio de esta compraventa, la suma de CIENTO CUARENTA MIL EUROS (140.000,00 €).
Valor de referencia del inmueble que es (107.317,62 €).
Designa como representante frente a la Hacienda a la mercantil “ZENIA ABOGADOS, SOCIEDAD LIMITADA PROFESIONAL”.
TITULO.- herencia de su esposo, el día 12 de Abril de 2016, número 527 de protocolo.
''';
    expect(deedPeople(deed).first.nie, 'X7183596Y');
    final facts = extractDeedFacts(deed);
    expect(facts.sellers.map((p) => p.nie), ['X7183596Y']);
    expect(facts.buyers.map((p) => p.nie), ['Y9736943E', 'Y9737090P']);
    expect(facts.buyers.any((p) => p.name.contains('SOPHIE')), isFalse);
    expect(facts.salePrice, '140000.00');
    expect(facts.referenceValue, '107317.62');
    expect(facts.cadastral, '8443304XH9184S0025KY');
    expect(facts.lawyer, contains('ZENIA ABOGADOS'));
    expect(facts.parcela, 'R-2.2');
    expect(facts.address, contains('calle Islandia'));
    expect(facts.address, contains('catorce'));
    expect(
      extractDeedFacts(
        'URBANA.- Vivienda en término de Algorfa, hoy avenida de la Vega, número 12.',
      ).address,
      'avenida de la Vega, 12, Algorfa',
    );
    expect(
      looksLikeEscrituraText(
        'FACTURA 88,50 €. Según escritura de compraventa ante notario. Comprador Ana.',
      ),
      isFalse,
    );
    final aligned = alignDeedFieldsToCliente(
      fields: {
        'fields.nombre': 'PATRICIA FRANCIS DAVIDSON',
        'fields.nie': 'X7183596Y',
        'fields.tel': '557432941',
        'fields.protocol': '2016',
      },
      bodyText: deed,
      clienteNombre: 'Petr Sokol',
      clienteNie: 'Y9736943E',
    );
    expect(aligned['fields.nombre'], 'Petr Sokol');
    expect(aligned['fields.nie'], 'Y9736943E');
    expect(aligned['fields.buyers'], contains('PETR SOKOL'));
    expect(aligned['fields.buyers'], contains('MONIKA'));
    expect(aligned['fields.sellers'], contains('PATRICIA'));
    expect(aligned['fields.sellerNie'], 'X7183596Y');
    expect(aligned['fields.protocol'], '2116');
    expect(aligned['fields.salePrice'], '140000.00');
    expect(aligned.containsKey('fields.tel'), isFalse);
    expect(
      documentFitsCliente(
        cardName: 'Petr Sokol',
        cardNie: 'Y-9736943-E',
        fields: aligned,
      ),
      isTrue,
    );
    expect(
      documentFitsCliente(
        cardName: 'Petr Sokol',
        cardNie: 'Y9736943E',
        fields: {
          'fields.nombre': 'PATRICIA FRANCIS DAVIDSON',
          'fields.nie': 'X7183596Y',
        },
      ),
      isFalse,
    );
    final padded = '${'x' * 5000}\n$deed';
    expect(escrituraLlmFocus(padded), contains('PETR SOKOL'));
    expect(spanishDeedNumber(deed), 2116);
    expect(
      deedBelongsToCliente(
        cardName: 'Petr Sokol',
        cardNie: 'Y9736943E',
        bodyText: deed,
        paper: aligned,
      ),
      isTrue,
    );
    expect(
      proposeFolderLadoFromDeed(
        facts: facts,
        clienteNombre: 'Petr Sokol',
        clienteNie: 'Y9736943E',
      ),
      'comprador',
    );
    expect(
      proposeFolderLadoFromDeed(
        facts: facts,
        clienteNombre: 'Patricia Francis Davidson',
        clienteNie: 'X7183596Y',
      ),
      'vendedor',
    );
    expect(aligned['fields.folderLado'], 'comprador');
    final proposed = proposeTitularesFromDeed(facts);
    expect(
      proposed.where((t) => t.lado == 'comprador').map((t) => t.nieNormalized),
      ['Y9736943E', 'Y9737090P'],
    );
    expect(
      proposed.where((t) => t.lado == 'comprador').map((t) => t.cuotaBps),
      [5000, 5000],
    );
    expect(proposed.where((t) => t.lado == 'vendedor').map((t) => t.cuotaBps), [
      10000,
    ]);
    expect(
      matchTitularClienteId(
        row: proposed.firstWhere((t) => t.nieNormalized == 'Y9736943E'),
        nieToClienteId: const {'Y9736943E': 'petr-id'},
      ),
      'petr-id',
    );
    expect(
      matchTitularClienteId(
        row: proposed.firstWhere((t) => t.nieNormalized == 'Y9737090P'),
        nieToClienteId: const {'Y9736943E': 'petr-id'},
      ),
      isNull,
    );
  });

  test('Rychnov nad Kněžnou není příjmení kupujícího', () {
    const deed = '''
COMPRAVENTA
COMPARECEN:
DE UNA PARTE Y PARA VENDER:
Dª PATRICIA FRANCIS DAVIDSON, de soltera AYRES, nacida el día 16 de Marzo de 1955,
de nacionalidad británica, con N.I.E. número X-7183596-Y.
Y DE OTRA, PARA COMPRAR:
Dª SOPHIE ELIZABETH RODRIGUEZ FITZ-HENRY, nacida el día 30 de Septiembre de 1983,
de nacionalidad británica, con N.I.E. número X-8764216-C.
INTERVIENEN: A) La Sra. Rodríguez Fitz-Henry interviene en nombre y representación
de los cónyuges D. PETR SOKOL, nacido el día 5 de Junio de 1987, y Dª MONIKA SOKOLOVA,
nacida el día 16 de Abril de 1985, de nacionalidad de la República Checa, con residencia
en la República Checa, en Rampuse, 5, 516 01, Rychnov
Nad Kneznou, con pasaportes de su nacionalidad números 43927578 y 46089086,
respectivamente, y con N.I.E. números Y-9736943-E e Y-9737090-P, respectivamente.
EXPONEN:
URBANA.- Vivienda en término de Algorfa.
''';
    expect(looksLikeDeedPersonName('Kneznou'), isFalse);
    expect(looksLikeDeedPersonName('Kneznov'), isFalse);
    expect(looksLikeDeedPersonName('británica'), isFalse);
    expect(looksLikeDeedPersonName('PETR SOKOL'), isTrue);
    final facts = extractDeedFacts(deed);
    expect(facts.sellers.map((p) => p.nie), ['X7183596Y']);
    expect(facts.sellers.first.name, contains('PATRICIA'));
    expect(facts.buyers.map((p) => p.nie), ['Y9736943E', 'Y9737090P']);
    for (final b in facts.buyers) {
      expect(b.name.toLowerCase(), isNot(contains('knezn')));
      expect(b.name.toLowerCase(), isNot(contains('británica')));
    }
    expect(facts.buyers[0].name, contains('PETR'));
    expect(facts.buyers[1].name, contains('MONIKA'));
    final shown = displayDocumentoFields(
      fields: {
        'fields.buyers': 'Kneznov (Y9736943E); Kneznov (Y9737090P)',
        'fields.seller': 'británica',
        'body_text': deed,
      },
      clienteNombre: 'Petr Sokol',
      clienteNie: 'Y9736943E',
    );
    expect(shown['fields.buyers'], contains('PETR SOKOL'));
    expect(shown['fields.buyers'], contains('MONIKA'));
    expect(shown['fields.buyers']!.toLowerCase(), isNot(contains('knezn')));
    expect(shown['fields.sellers'], contains('PATRICIA'));
  });

  test('cizí listina nezapíše titulares ani po vepsání jména karty', () {
    const deed = '''
COMPRAVENTA
COMPARECEN:
DE UNA PARTE Y PARA VENDER:
Dª PATRICIA FRANCIS DAVIDSON, nacida el día 16 de Marzo de 1955,
con N.I.E. número X-7183596-Y.
Y DE OTRA, PARA COMPRAR:
Dª MONIKA SOKOLOVA, nacida el día 16 de Abril de 1985, con N.I.E. número Y-9737090-P.
''';
    expect(looksLikeEscrituraText(deed), isTrue);
    expect(extractDeedFacts(deed).buyers.map((p) => p.nie), ['Y9737090P']);
    final aligned = alignDeedFieldsToCliente(
      fields: {'fields.nombre': 'MONIKA SOKOLOVA', 'fields.nie': 'Y9737090P'},
      bodyText: deed,
      clienteNombre: 'Petr Sokol',
      clienteNie: 'Y9736943E',
    );
    expect(aligned['fields.nombre'], 'Petr Sokol');
    expect(
      deedBelongsToCliente(
        cardName: 'Petr Sokol',
        cardNie: 'Y9736943E',
        bodyText: deed,
        paper: aligned,
      ),
      isFalse,
    );
    expect(
      deedBelongsToCliente(
        cardName: 'Petr Sokol',
        cardNie: null,
        bodyText: deed,
        paper: aligned,
      ),
      isFalse,
    );
    expect(
      documentFitsCliente(
        cardName: 'Petr Sokol',
        cardNie: 'Y9736943E',
        fields: aligned,
      ),
      isFalse,
    );
  });

  test('compraventa se dvěma prodávajícími bez zmocněnce', () {
    const deed = '''
ESCRITURA DE COMPRAVENTA
NUMERO CIENTO VEINTITRÉS.
Ante mí, MARIA GOMEZ RUIZ, Notario del Ilustre Colegio de Murcia,
COMPARECEN:
DE UNA PARTE Y PARA VENDER:
D. JUAN PEREZ LOPEZ, nacido el día 1 de Enero de 1960, con N.I.E. número X-1111111-A,
y Dª ANA PEREZ LOPEZ, nacida el día 2 de Enero de 1962, con N.I.E. número X-2222222-B.
Y DE OTRA, PARA COMPRAR:
D. LUIS GARCIA MARTIN, nacido el día 3 de Marzo de 1980, con N.I.E. número Y-3333333-C.
EXPONEN:
URBANA.- Vivienda en término de Torrevieja, parcela 12.
OTORGAN:
Es precio de esta compraventa la suma de OCHENTA MIL EUROS (80.000,00 €).
REFERENCIA CATASTRAL. - 1234567XH1234S0001AB
''';
    final facts = extractDeedFacts(deed);
    expect(facts.sellers.map((p) => p.nie).toList(), [
      'X1111111A',
      'X2222222B',
    ]);
    expect(facts.buyers.map((p) => p.nie).toList(), ['Y3333333C']);
    expect(facts.representatives, isEmpty);
    expect(facts.salePrice, '80000.00');
    final aligned = alignDeedFieldsToCliente(
      fields: const {},
      bodyText: deed,
      clienteNombre: 'Luis Garcia',
      clienteNie: 'Y3333333C',
    );
    expect(aligned['fields.nombre'], 'Luis Garcia');
    expect(aligned['fields.sellers']!.split(';'), hasLength(2));
    final proposed = proposeTitularesFromDeed(facts);
    expect(splitCuotaBps(3), [3333, 3333, 3334]);
    expect(sharePercentFromBps(5000), '50');
    expect(proposed.where((t) => t.lado == 'vendedor').map((t) => t.cuotaBps), [
      5000,
      5000,
    ]);
    expect(
      proposed.where((t) => t.lado == 'comprador').map((t) => t.cuotaBps),
      [10000],
    );
    expect(
      titularNeedsCoOwnerCard(
        isComprador: true,
        clienteId: null,
        nieNormalized: 'Y9737090P',
      ),
      isTrue,
    );
    expect(
      titularNeedsCoOwnerCard(
        isComprador: true,
        clienteId: 'petr-id',
        nieNormalized: 'Y9736943E',
      ),
      isFalse,
    );
    expect(
      titularNeedsCoOwnerCard(
        isComprador: false,
        clienteId: null,
        nieNormalized: 'X7183596Y',
      ),
      isFalse,
    );
    expect(identifierKindFromNormalized('Y9737090P'), 'nie');
    final prepared = prepareDocumentoExtract(
      fields: {
        'fields.nombre': 'PATRICIA',
        'body_text': '''
COMPRAVENTA
COMPARECEN:
DE UNA PARTE Y PARA VENDER:
Dª PATRICIA FRANCIS DAVIDSON, nacida el día 16 de Marzo de 1955,
con N.I.E. número X-7183596-Y.
Y DE OTRA, PARA COMPRAR:
D. PETR SOKOL, nacido el día 5 de Junio de 1987, con N.I.E. número Y-9736943-E.
''',
      },
      existingBody: '',
      currentTipo: 'other',
      cardName: 'Petr Sokol',
      cardNie: 'Y9736943E',
    );
    expect(prepared.deed, isTrue);
    expect(prepared.nextTipo, 'copia_escritura');
    expect(prepared.fields['fields.buyers'], contains('PETR SOKOL'));
  });

  test('na listině je i DNI Španěla, nejen NIE', () {
    const deed = '''
ESCRITURA DE COMPRAVENTA
COMPARECEN:
DE UNA PARTE Y PARA VENDER:
D. JUAN PEREZ LOPEZ, nacido el día 1 de Enero de 1960, con D.N.I. número 12345678A.
Y DE OTRA, PARA COMPRAR:
D. LUIS GARCIA MARTIN, nacido el día 3 de Marzo de 1980, con N.I.E. número Y-3333333-C.
''';
    final facts = extractDeedFacts(deed);
    expect(facts.sellers.map((p) => p.nie).toList(), ['12345678A']);
    expect(facts.buyers.map((p) => p.nie).toList(), ['Y3333333C']);
  });

  test('druhý Guardar doplní prázdné NIE, cuota a ruční NIE nechá', () {
    final proposed = proposeTitularesFromDeed(
      const DeedFacts(
        buyers: [
          DeedPerson(nie: 'Y9736943E', name: 'PETR SOKOL', index: 1),
          DeedPerson(nie: 'Y9737090P', name: 'MONIKA SOKOLOVA', index: 2),
        ],
      ),
    );
    final patches = planFillEmptyTitulares(
      existing: const [
        LiveTitularRow(
          id: 'petr',
          lado: 'comprador',
          nombre: 'Petr Sokol',
          nieNormalized: '',
        ),
        LiveTitularRow(
          id: 'monika',
          lado: 'comprador',
          nombre: 'Monika Sokolova',
          nieNormalized: 'Y9737090P',
        ),
      ],
      proposed: proposed,
    );
    expect(patches, hasLength(1));
    expect(patches.single.id, 'petr');
    expect(patches.single.nieNormalized, 'Y9736943E');
    expect(
      planFillEmptyTitulares(
        existing: const [
          LiveTitularRow(
            id: 'petr',
            lado: 'comprador',
            nombre: 'Petr Sokol',
            nieNormalized: 'Y9736943E',
          ),
        ],
        proposed: proposed,
      ),
      isEmpty,
    );
  });
}
