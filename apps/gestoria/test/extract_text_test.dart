import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/ai/documento_fields.dart';
import 'package:gestoria_os/features/ai/extract_text.dart';
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

  test('stoh faktur řadí od nejnovějšího období', () {
    expect(isInvoiceDocTipo('factura_agua'), isTrue);
    expect(isInvoiceDocTipo('contrato_agua'), isFalse);
    expect(
      paperSortStamp({'fields.periodTo': '2024-09-30', 'fields.issued': '2024-09-23'}),
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

  test('klient zůstane na deskách, voda se otevírá', () {
    expect(
      compraventaBloques.firstWhere((b) => b.key == 'cliente_snapshot').opensFromDesk,
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
}
