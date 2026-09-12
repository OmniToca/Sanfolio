import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/documents/bloque_field_keys.dart';
import 'package:gestoria_os/core/documents/documento_storage.dart';
import 'package:gestoria_os/core/documents/office_file_pick.dart';
import 'package:gestoria_os/features/ai/extract_text.dart';

void main() {
  test('cesta nahrání je tenant/cliente/soubor, ne card ani ai', () {
    const tenant = '11111111-1111-1111-1111-111111111111';
    const cliente = '22222222-2222-2222-2222-222222222222';
    final path = documentoStoragePath(
      tenantId: tenant,
      clienteId: cliente,
      originalName: 'nie_petr.pdf',
    );
    expect(path.startsWith('$tenant/$cliente/'), isTrue);
    expect(path.contains('/card/'), isFalse);
    expect(path.contains('/ai/'), isFalse);
    expect(path.endsWith('_nie_petr.pdf'), isTrue);
    expect(
      documentoPathInTenant(path: path, tenantId: tenant, clienteId: cliente),
      isTrue,
    );
    expect(
      documentoPathInTenant(
        path: path,
        tenantId: tenant,
        clienteId: '33333333-3333-3333-3333-333333333333',
      ),
      isFalse,
    );
    expect(
      documentoPathInTenant(
        path: '$tenant/../other/x',
        tenantId: tenant,
      ),
      isFalse,
    );
  });

  test('složka v cestě nesmí obsahovat lomítko z názvu', () {
    const tenant = '11111111-1111-1111-1111-111111111111';
    const cliente = '22222222-2222-2222-2222-222222222222';
    final path = documentoStoragePath(
      tenantId: tenant,
      clienteId: cliente,
      originalName: 'a/b\\c.pdf',
    );
    expect(path.split('/').length, 3);
    expect(path.contains('a/b'), isFalse);
  });

  test('dodavatel se čte z fields.company i ze starého proveedor', () {
    expect(
      bloqueField({'fields.company': 'Iberdrola'}, 'fields.company'),
      'Iberdrola',
    );
    expect(
      bloqueField({'proveedor': 'Endesa'}, 'fields.company'),
      'Endesa',
    );
    expect(
      bloqueField({'fecha_vencimiento': '2026-12-01'}, 'fields.expiry'),
      '2026-12-01',
    );
    expect(bloqueField(const {}, 'fields.company'), isNull);
  });

  test('faktura bez přípony je pořád PDF', () {
    final pdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31]);
    expect(sniffOfficeExtension(pdf), 'pdf');
    expect(mimeForOfficeFile('factura.pdf'), 'application/pdf');
    expect(mimeForOfficeFile('pas.heic'), 'image/heic');
  });

  test('přepis oddělí body_text od polí desky', () {
    final t = splitDocumentoTranscript({
      'fields.company': 'Iberdrola',
      'body_text': '--- Strana 1/2 ---\nContrato',
    });
    expect(t.fields['fields.company'], 'Iberdrola');
    expect(t.fields.containsKey('body_text'), isFalse);
    expect(t.bodyText, contains('Contrato'));
  });
}
