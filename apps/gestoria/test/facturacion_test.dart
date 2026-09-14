import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/modules/module_catalog.dart';
import 'package:gestoria_os/features/ai/documento_fields.dart';
import 'package:gestoria_os/features/facturacion/factura.dart';
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
}
