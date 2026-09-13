import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/modules/module_catalog.dart';
import 'package:gestoria_os/features/ai/documento_fields.dart';
import 'package:gestoria_os/features/facturacion/factura.dart';

void main() {
  test('modul facturacion má klíč do organization_modules', () {
    expect(GestoriaModule.facturacion.key, 'facturacion');
    expect(GestoriaModuleKey.fromKey('facturacion'), GestoriaModule.facturacion);
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
