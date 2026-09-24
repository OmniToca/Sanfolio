import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/documents/documento_storage.dart';
import 'package:gestoria_os/core/documents/office_file_pick.dart';
import 'package:gestoria_os/features/ai/extract_queue.dart';
import 'package:gestoria_os/features/ai/extract_text.dart';
import 'package:gestoria_os/features/carpeta/carpeta_routes.dart';
import 'package:gestoria_os/features/carpeta/stoh.dart';
import 'package:gestoria_os/features/carpeta/stoh_queue.dart';
import 'package:gestoria_os/features/carpeta/carpeta_controller.dart';
import 'package:gestoria_os/features/ai/ai_providers.dart';

void main() {
  test('Hidraqua faktura patří na vodu, Guardar zapne vypnutý blok', () {
    final proposal = classifyStohPaper(
      originalName: 'Hidraqua_factura.pdf',
      bodyText: 'Hidraqua Periodo de facturación TRIMESTRAL',
    );
    expect(proposal.bloqueKey, 'agua');
    expect(proposal.tipo, 'factura_agua');
    final plan = planStohGuardar(
      selectedBloqueKey: proposal.bloqueKey,
      selectedTipo: proposal.tipo,
      bloqueCurrentlyEnabled: false,
    );
    expect(plan, isNotNull);
    expect(plan!.enableBloque, isTrue);
    expect(plan.bloqueKey, 'agua');
  });

  test('Cta bancaria agencia je IBAN na kartě, ne telefon', () {
    final proposal = classifyStohPaper(
      originalName: 'Cta bancaria agencia.pdf',
      bodyText: '''
NOMBRE DE LA CUENTA/ACCOUNT NAME: LA MARINA SERVICES INTERNATIONAL
IBAN: ES96 2100 9143 9413 0049 8086
BIC: CAIXESBBXXX
''',
    );
    expect(proposal.bloqueKey, 'cliente_snapshot');
    expect(proposal.tipo, 'justificante_iban');
  });

  test('scan bez slova Cta: Beneficiary + IBAN je pořád účet', () {
    final proposal = classifyStohPaper(
      originalName: 'scan_01.pdf',
      bodyText: '''
Beneficiary
Renata Susicova
IBAN
ES10 1583 0001 1190 1063 9767
BIC/SWIFT code
REVOESM2
''',
      fields: const {'fields.iban': 'ES1015830001119010639767'},
    );
    expect(proposal.bloqueKey, 'cliente_snapshot');
    expect(proposal.tipo, 'justificante_iban');
  });

  test('CUPS a kWh patří na luz; zapnutý blok se znovu nezapíná', () {
    final proposal = classifyStohPaper(
      originalName: 'iberdrola.pdf',
      fields: const {'fields.cups': 'ES0021000012345678AB'},
    );
    expect(proposal.bloqueKey, 'luz');
    final plan = planStohGuardar(
      selectedBloqueKey: 'luz',
      selectedTipo: 'factura_luz',
      bloqueCurrentlyEnabled: true,
    );
    expect(plan!.enableBloque, isFalse);
  });

  test('SUMA TOTAL na faktuře není IBI; CUPS bez kWh není elektřina', () {
    expect(
      classifyStohPaper(
        originalName: 'Hidraqua_factura.pdf',
        bodyText: 'Hidraqua SUMA TOTAL 88,50 EUR Periodo TRIMESTRAL',
      ).bloqueKey,
      'agua',
    );
    expect(
      classifyStohPaper(
        originalName: 'recibo.pdf',
        bodyText: 'RECIBO IBI SUMA Gestión Tributaria Ejercicio 2024',
      ).bloqueKey,
      'suma',
    );
    expect(
      classifyStohPaper(
        originalName: 'scan.pdf',
        fields: const {'fields.cups': 'ES0021000012345678AB'},
      ).known,
      isFalse,
    );
    expect(
      classifyStohPaper(
        originalName: 'contrato_gas.pdf',
        bodyText: 'Gas natural CUPS ES0212345678901234AB',
        fields: const {'fields.cups': 'ES0212345678901234AB'},
      ).bloqueKey,
      'gaz',
    );
  });

  test('escritura a DNI se nepletou; nejistota zůstane prázdná', () {
    expect(
      classifyStohPaper(originalName: 'copia_escritura_notario.pdf').bloqueKey,
      'escritura',
    );
    expect(
      classifyStohPaper(originalName: 'pasaporte_ana.jpg').tipo,
      'pasaporte',
    );
    expect(
      classifyStohPaper(originalName: 'ESC Final Renata.pdf').bloqueKey,
      'escritura',
    );
    expect(
      classifyStohPaper(originalName: 'ESC Ampliacion de obra.pdf').tipo,
      'copia_escritura',
    );
    expect(
      classifyStohPaper(
        originalName: 'scan_01.pdf',
        bodyText: '''
--- Strana 1/45 ---
ESCRITURA DE COMPRAVENTA
NÚMERO MIL CIENTO SETENTA Y CINCO
Ante mí, ALICIA RUIZ TORREGROSA, Notario
COMPARECEN:
La parte compradora: RENATA
''',
        fields: const {kProposedBloqueKey: 'cliente_snapshot'},
      ).bloqueKey,
      'escritura',
    );
    expect(
      classifyStohPaper(
        originalName: 'scan_02.pdf',
        bodyText: '''
ESCRITURA DE AMPLIACIÓN DE OBRA
NÚMERO CUATROCIENTOS TREINTA Y SIETE
Ante mí, ALICIA RUIZ TORREGROSA, Notario
''',
      ).bloqueKey,
      'escritura',
    );
    expect(
      stohDocumentTitle(
        '--- Strana 1/45 ---\n- Folio 1 -\nESCRITURA DE COMPRAVENTA\nNÚMERO MIL',
      ),
      'ESCRITURA DE COMPRAVENTA',
    );
    expect(
      classifyStohPaper(
        originalName: 'Valor de referencia.pdf',
        bodyText: '''
CERTIFICACIÓN CATASTRAL
DE VALOR DE REFERENCIA
Referencia catastral:
''',
      ).tipo,
      'certificado_catastral',
    );
    expect(
      classifyStohPaper(originalName: 'Valor de referenci.pdf').bloqueKey,
      'plusvalia',
    );
    expect(
      classifyStohPaper(originalName: 'scan001.pdf').known,
      isFalse,
    );
    expect(
      classifyStohPaper(
        originalName: 'Poder Mark Howells Regalado.pdf',
        bodyText: 'Ante mí, notario, protocolo 2116 escritura de poder',
      ).bloqueKey,
      'poder',
    );
    expect(
      classifyStohPaper(
        originalName: 'FACTURA 00000057_R Susicova.pdf',
        bodyText: 'Factura. Protocolo notarial. Escritura.',
        fields: const {kProposedBloqueKey: 'escritura'},
      ).bloqueKey,
      isNot('escritura'),
    );
    expect(
      classifyStohPaper(
        originalName: 'Gana_Energia_marzo.pdf',
        bodyText: 'Gana Energía. Periodo de facturación.',
        fields: const {'fields.company': 'Gana Energía'},
      ).bloqueKey,
      'luz',
    );
    expect(planStohGuardar(
      selectedBloqueKey: '',
      selectedTipo: 'other',
      bloqueCurrentlyEnabled: false,
    ), isNull);
  });

  test('proposed z extract má přednost; Guardar je neschová do extracted', () {
    final proposal = classifyStohPaper(
      originalName: 'scan.pdf',
      fields: const {
        kProposedBloqueKey: 'seguro',
        kProposedTipo: 'poliza_seguro',
        'fields.company': 'Mapfre',
      },
    );
    expect(proposal.bloqueKey, 'seguro');
    final yellow = extractProposalFields({
      kProposedBloqueKey: 'seguro',
      kProposedTipo: 'poliza_seguro',
      kExtractStatus: 'pending',
      'body_text': 'póliza',
      'fields.company': 'Mapfre',
    });
    expect(yellow, {'fields.company': 'Mapfre'});
  });

  test('cesta stoh je tenant/cliente/stoh, ne blok', () {
    const tenant = '11111111-1111-1111-1111-111111111111';
    const cliente = '22222222-2222-2222-2222-222222222222';
    final path = documentoStoragePath(
      tenantId: tenant,
      clienteId: cliente,
      originalName: 'nie.pdf',
      stoh: true,
    );
    expect(isStohStoragePath(path), isTrue);
    expect(path.split('/')[2], 'stoh');
    expect(path.split('/').length, 4);
    expect(officeFileBatchMax, 40);
  });

  test('fronta /stoh páruje draft podle storage_path', () {
    const doc = CarpetaDocumento(
      id: 'd1',
      tipo: 'other',
      storagePath: 't/c/stoh/x_factura.pdf',
      originalName: 'Hidraqua.pdf',
    );
    final rows = mergeStohQueue(
      documents: const [doc],
      drafts: const [
        AiPrefillDraft(
          clienteId: 'c',
          bloqueKey: 'agua',
          storagePath: 't/c/stoh/x_factura.pdf',
          draftId: 'dr1',
          fields: {kProposedBloqueKey: 'agua', 'fields.amount': '188.85'},
        ),
      ],
    );
    expect(rows.single.draftId, 'dr1');
    expect(rows.single.proposal.bloqueKey, 'agua');
  });

  test('po založení klienta jde URL na /stoh, ne rovnou na desku', () {
    expect(carpetaStohRoute('abc', afterCreate: true), '/clientes/abc/stoh?new=1');
    expect(carpetaRoute('abc'), '/clientes/abc/carpeta');
    expect(
      carpetaRoute('abc', afterSkip: true),
      '/clientes/abc/carpeta?skip=1',
    );
    expect(
      carpetaBloqueRoute('abc', 'agua', expedienteId: 'e1'),
      '/clientes/abc/carpeta/agua?exp=e1',
    );
  });

  test('nahraný stoh ukáže kus z celku a procenta', () {
    expect(stohUploadPercent(done: 0, total: 38), 0);
    expect(stohUploadPercent(done: 19, total: 38), 50);
    expect(stohUploadPercent(done: 38, total: 38), 100);
    expect(stohUploadPercent(done: 1, total: 0), 0);
    expect(stohUploadFraction(done: 19, total: 38), 0.5);
  });

  test('soubory z dialogu se kopírují dřív, než input spadne', () {
    final live = ['a.pdf', 'b.pdf', 'c.pdf'];
    final copy = takeIndexedBatch(live.length, (i) => live[i]);
    live.clear();
    expect(copy, ['a.pdf', 'b.pdf', 'c.pdf']);
    expect(
      takeIndexedBatch(officeFileBatchMax + 3, (i) => i).length,
      officeFileBatchMax,
    );
  });
}
