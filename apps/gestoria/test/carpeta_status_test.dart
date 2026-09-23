import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/theme/app_theme.dart';
import 'package:gestoria_os/features/carpeta/bloque_template.dart';
import 'package:gestoria_os/features/carpeta/carpeta_controller.dart';
import 'package:gestoria_os/features/carpeta/carpeta_screen.dart';
import 'package:gestoria_os/features/clientes/clientes_providers.dart';

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

  test('vypnuté escritura bez papírů není složka', () {
    const empty = BloqueState(enabled: false);
    expect(emptyOffBloque(empty), isTrue);
    expect(
      emptyOffBloque(
        const BloqueState(
          enabled: false,
          documents: [
            CarpetaDocumento(
              id: 'd1',
              tipo: 'copia_escritura',
              storagePath: 't/c/e.pdf',
              originalName: 'escritura.pdf',
            ),
          ],
        ),
      ),
      isFalse,
    );
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

  test('zelená je jen done, díra dokumentu není mint', () {
    expect(bloqueStatusFill(BloqueUiStatus.done), AppTheme.statusOkSoft);
    expect(
      bloqueStatusFill(BloqueUiStatus.missingDocument),
      AppTheme.statusAlertSoft,
    );
    expect(
      bloqueStatusFill(BloqueUiStatus.missingData),
      AppTheme.statusWarnSoft,
    );
    expect(
      bloqueStatusFill(BloqueUiStatus.watching),
      AppTheme.statusWatchSoft,
    );
    expect(AppTheme.accent, isNot(AppTheme.statusOk));
  });

  test('voda s fakturou nemá lištu 1/3', () {
    const template = BloqueTemplate(
      key: 'agua',
      fieldKeys: ['fields.company'],
      requiredDocTypes: ['contrato_agua', 'factura_agua', 'recibo_agua'],
      requiredDocsMode: RequiredDocsMode.any,
    );
    const withInvoice = BloqueState(
      enabled: true,
      documents: [
        CarpetaDocumento(
          id: 'd1',
          tipo: 'factura_agua',
          storagePath: 't/c/f.pdf',
          originalName: 'f.pdf',
        ),
      ],
    );
    final hint = bloqueDocsHint(template, withInvoice)!;
    expect(hint.satisfied, isTrue);
    expect(hint.showBar, isFalse);
  });

  test('all se dvěma typy ukáže lištu jen když něco chybí', () {
    const template = BloqueTemplate(
      key: 'modelo_210',
      fieldKeys: ['fields.deadline'],
      requiredDocTypes: ['recibo_ibi', 'certificado_catastral'],
    );
    const empty = BloqueState(enabled: true);
    final missing = bloqueDocsHint(template, empty)!;
    expect(missing.satisfied, isFalse);
    expect(missing.showBar, isTrue);
    expect(missing.missingTypes, ['recibo_ibi', 'certificado_catastral']);
    const full = BloqueState(
      enabled: true,
      documents: [
        CarpetaDocumento(
          id: 'a',
          tipo: 'recibo_ibi',
          storagePath: 't/a',
          originalName: 'a.pdf',
        ),
        CarpetaDocumento(
          id: 'b',
          tipo: 'certificado_catastral',
          storagePath: 't/b',
          originalName: 'b.pdf',
        ),
      ],
    );
    expect(bloqueDocsHint(template, full)!.satisfied, isTrue);
    expect(bloqueDocsHint(template, full)!.showBar, isFalse);
  });

  test('podíl kupujících varuje, když není 100 %', () {
    const petr = InmuebleTitular(
      id: '1',
      nombre: 'Petr',
      nieRaw: 'Y9736943E',
      lado: 'comprador',
      cuotaBps: 5000,
    );
    const monika = InmuebleTitular(
      id: '2',
      nombre: 'Monika',
      nieRaw: 'Y9737090P',
      lado: 'comprador',
      cuotaBps: 4000,
    );
    const seller = InmuebleTitular(
      id: '3',
      nombre: 'Patricia',
      nieRaw: 'X7183596Y',
      lado: 'vendedor',
      cuotaBps: 10000,
    );
    expect(compradorCuotaBpsSum([petr, monika]), 9000);
    expect(compradorCuotaBpsSum([petr, monika.copyWith(cuotaBps: 5000)]), 10000);
    expect(
      petr.copyWith(nieRaw: 'Y0000000A', nombre: 'Petr Sokol').cuotaBps,
      petr.cuotaBps,
    );
    expect(compradorCuotaBpsSum([petr, monika, seller]), 9000);
    expect(
      titularSharePercentForCliente(
        rows: [
          InmuebleTitular(
            id: '1',
            nombre: 'Petr',
            nieRaw: 'Y9736943E',
            lado: 'comprador',
            cuotaBps: 5000,
            clienteId: 'petr-id',
          ),
          monika,
          seller,
        ],
        clienteId: 'petr-id',
      ),
      '50',
    );
    expect(
      titularSharePercentForCliente(
        rows: [monika, petr],
        clienteId: 'other',
        clienteNie: 'Y9736943E',
      ),
      '50',
    );
    expect(
      folderLadoFromTitulares(
        rows: [petr.copyWith(), monika, seller],
        clienteId: 'petr-id',
      ),
      isNull,
    );
    expect(
      folderLadoFromTitulares(
        rows: [
          InmuebleTitular(
            id: '1',
            nombre: 'Petr',
            nieRaw: 'Y9736943E',
            lado: 'comprador',
            cuotaBps: 5000,
            clienteId: 'petr-id',
          ),
          seller,
        ],
        clienteId: 'petr-id',
      ),
      'comprador',
    );
    expect(
      folderLadoFromTitulares(
        rows: [seller.copyWith(clienteId: 'pat-id')],
        clienteId: 'pat-id',
      ),
      'vendedor',
    );
    expect(
      folderLadoFromTitulares(
        rows: [seller],
        clienteId: 'nobody',
        clienteNie: 'X7183596Y',
      ),
      'vendedor',
    );
    expect(
      titularSharePercentForCliente(
        rows: [seller.copyWith(clienteId: 'pat-id')],
        clienteId: 'pat-id',
      ),
      '100',
    );
    expect(normalizeFolderLado('comprador'), 'comprador');
    expect(normalizeFolderLado('x'), isNull);
  });

  test('spoluvlastník v seznamu není prázdná složka', () {
    const row = ClienteRow(
      id: 'm',
      nombre: 'Monika',
      status: 'activo',
      nie: 'Y9737090P',
      coOwnerNombre: 'Petr Sokol',
      coOwnerAddress: 'Islandia 14',
    );
    expect(row.isCoOwnerOnly, isTrue);
    expect(row.subtitle, 'Y9737090P');
    const owner = ClienteRow(
      id: 'p',
      nombre: 'Petr Sokol',
      status: 'activo',
    );
    expect(owner.isCoOwnerOnly, isFalse);
  });
}
