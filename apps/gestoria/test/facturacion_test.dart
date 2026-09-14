import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/modules/module_catalog.dart';
import 'package:gestoria_os/features/ai/documento_fields.dart';
import 'package:gestoria_os/features/facturacion/factura.dart';
import 'package:gestoria_os/features/facturacion/factura_kpi.dart';
import 'package:gestoria_os/features/facturacion/factura_lineas.dart';
import 'package:gestoria_os/features/facturacion/factura_print_html.dart';
import 'package:gestoria_os/features/facturacion/facturacion_nav.dart';
import 'package:gestoria_os/features/facturacion/sif_emit.dart';
import 'package:gestoria_os/features/facturacion/sif_qr.dart';

void main() {
  test('modul facturacion má klíč do organization_modules', () {
    expect(GestoriaModule.facturacion.key, 'facturacion');
    expect(GestoriaModuleKey.fromKey('facturacion'), GestoriaModule.facturacion);
  });

  test('vydaná bez uuid jde Emitir, s uuid jen Ověřit', () {
    const draft = Factura(
      id: '1',
      direccion: 'emitida',
      estado: 'borrador',
    );
    expect(draft.canEmitir, isTrue);
    expect(draft.canVerificar, isFalse);
    expect(draft.hasDestinatario, isFalse);

    const queued = Factura(
      id: '2',
      direccion: 'emitida',
      estado: 'pendiente',
      destinatarioNombre: 'Petr Sokol',
      destinatarioNif: 'Y9736943E',
      sifExternalId: 'uuid-1',
      sifStatus: 'Pendiente',
    );
    expect(queued.canEmitir, isFalse);
    expect(queued.canVerificar, isTrue);
    expect(queued.hasDestinatario, isTrue);
  });

  test('sif snackbar rozliší frontu a chybějící NIF', () {
    expect(
      sifSnackKey(
        const SifCallResult(ok: true, bookEstado: 'pendiente'),
        verify: false,
      ),
      'facturacion.emitPending',
    );
    expect(
      sifSnackKey(
        const SifCallResult(ok: false, error: 'destinatario_required'),
        verify: false,
      ),
      'facturacion.destinatarioRequired',
    );
    expect(
      sifSnackKey(
        const SifCallResult(ok: true, bookEstado: 'emitida'),
        verify: true,
      ),
      'facturacion.verifyOk',
    );
  });

  test('přijatá z extractu počítá cents a NIF dodavatele, ne klienta', () {
    final d = recibidaFromExtract({
      'fields.company': 'Iberdrola Clientes',
      'fields.supplierNif': 'A95758389',
      'fields.invoiceNo': 'F-2026-18',
      'fields.issued': '2026-04-02',
      'fields.amount': '121,00',
      'fields.base': '100,00',
      'fields.iva': '21,00',
      'fields.ivaRate': '21',
      'fields.concept': 'Suministro',
    });
    expect(d.proveedorNombre, 'Iberdrola Clientes');
    expect(d.proveedorNif, 'A95758389');
    expect(d.numero, 'F-2026-18');
    expect(d.baseCents, 10000);
    expect(d.ivaCents, 2100);
    expect(d.totalCents, 12100);
    expect(d.ivaBps, 2100);
    expect(
      fieldsForDocTipo('factura_recibida'),
      containsAll(['fields.supplierNif', 'fields.base', 'fields.amount']),
    );
    expect(isInvoiceDocTipo('factura_recibida'), isTrue);
  });

  test('QR data-URI se dekóduje na PNG bajty', () {
    const payload = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2ZkAAAAASUVORK5CYII=';
    final bytes = sifQrPngBytes('data:image/png;base64,$payload');
    expect(bytes, isNotNull);
    expect(bytes!.first, 0x89);
    expect(sifQrPngBytes('https://prewww2.aeat.es/x'), isNull);
  });

  test('vnitřní knihy jsou Ventas/Compras, ne další rail', () {
    expect(facturacionGroups(), ['ventas', 'compras']);
    expect(facturacionLibroByKey('emitidas')?.direccion, 'emitida');
    expect(facturacionLibroByKey('recibidas')?.isCompras, isTrue);
  });

  test('KPI knihy sčítá rok a vencidas', () {
    final kpi = libroKpi(
      const [
        Factura(
          id: '1',
          direccion: 'emitida',
          estado: 'emitida',
          fecha: '2026-03-01',
          vencimiento: '2026-03-10',
          totalCents: 12100,
        ),
        Factura(
          id: '2',
          direccion: 'emitida',
          estado: 'pendiente',
          fecha: '2026-09-01',
          totalCents: 1000,
        ),
        Factura(
          id: '3',
          direccion: 'emitida',
          estado: 'emitida',
          fecha: '2025-01-01',
          totalCents: 99999,
        ),
      ],
      today: DateTime(2026, 9, 14),
      emitidas: true,
    );
    expect(kpi.year, 2026);
    expect(kpi.count, 2);
    expect(kpi.totalCents, 13100);
    expect(kpi.overdueCount, 1);
    expect(kpi.pendingCount, 1);
  });

  test('tisk vystavené je španělský papír s NIF a totalem', () {
    final html = facturaEmitidaPrintHtml(
      factura: const Factura(
        id: '1',
        direccion: 'emitida',
        estado: 'emitida',
        serie: 'A',
        numero: '3',
        fecha: '2026-09-14',
        destinatarioNombre: 'A <script>x</script>',
        destinatarioNif: 'Y9736943E',
        concepto: 'Honorarios',
        baseCents: 900,
        ivaCents: 189,
        totalCents: 1089,
        ivaBps: 2100,
        tipoFactura: 'F1',
      ),
      emisorNombre: 'Empresa de prueba SL',
      emisorNif: 'B75777847',
    );
    expect(html, contains('FACTURA'));
    expect(html, contains('B75777847'));
    expect(html, contains('Y9736943E'));
    expect(html, contains('10,89 €'));
    expect(html, contains('A &lt;script&gt;x&lt;/script&gt;'));
    expect(html, isNot(contains('<script>x</script>')));
    expect(html, contains('@page'));
    expect(html, contains('Emisor'));
    expect(html, contains('Destinatario'));
  });

  test('hledání a vencida podle kalendáře', () {
    const row = Factura(
      id: '1',
      direccion: 'emitida',
      estado: 'emitida',
      serie: 'A',
      numero: '3',
      destinatarioNombre: 'Ukážka Košice',
      destinatarioNif: 'Y9736943E',
      vencimiento: '2026-03-10',
    );
    expect(row.matchesQuery('kosice'), isTrue);
    expect(row.matchesQuery('A-3'), isTrue);
    expect(row.matchesQuery('xyz'), isFalse);
    expect(row.isVencida(DateTime(2026, 9, 14)), isTrue);
    expect(row.isVencida(DateTime(2026, 3, 10)), isFalse);
  });

  test('CSV knihy přijatých je středník a eura s čárkou', () {
    const row = Factura(
      id: '1',
      direccion: 'recibida',
      estado: 'guardada',
      proveedorNombre: 'Agua; Costa',
      proveedorNif: 'B12345678',
      numero: '12',
      fecha: '2026-03-01',
      clienteNombre: 'Petr Sokol',
      baseCents: 10000,
      ivaCents: 2100,
      totalCents: 12100,
    );
    final csv = receivedInvoicesCsv([row]);
    expect(csv, contains('fecha;proveedor;nif;numero;base;iva;total'));
    expect(csv, contains('2026-03-01;Agua, Costa;B12345678;12;100,00;21,00;121,00;Petr Sokol'));
  });

  test('obchodní řádky sčítají sazby a F2 nechce příjemce', () {
    final totals = totalsFromLineas([
      const FacturaLinea(
        descripcion: 'Honorarios',
        cantidad: 1,
        precioUnitarioCents: 10000,
        ivaBps: 2100,
      ),
      const FacturaLinea(
        descripcion: 'Suplido',
        cantidad: 2,
        precioUnitarioCents: 500,
        ivaBps: 0,
      ),
      const FacturaLinea(
        descripcion: 'Papel',
        cantidad: 1,
        precioUnitarioCents: 2000,
        ivaBps: 2100,
        descuentoBps: 1000,
      ),
    ]);
    // 100 + 10 (0 %) + 18 po 10% slevě z 20
    expect(totals.baseCents, 12800);
    expect(totals.ivaCents, 2478);
    expect(totals.totalCents, 15278);
    expect(totals.byRate, hasLength(2));
    expect(totals.exceedsF2Limit, isFalse);

    const f2 = Factura(
      id: '3',
      direccion: 'emitida',
      estado: 'borrador',
      tipoFactura: 'F2',
    );
    expect(f2.needsDestinatario, isFalse);
    expect(f2.hasDestinatario, isFalse);
    expect(f2.canEmitir, isTrue);

    expect(
      sifSnackKey(
        const SifCallResult(ok: false, error: 'f2_over_limit'),
        verify: false,
      ),
      'facturacion.f2OverLimit',
    );
  });
}
