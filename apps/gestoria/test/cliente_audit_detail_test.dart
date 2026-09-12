import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/clientes/cliente_audit.dart';

void main() {
  test('nahrání dokumentu nese název a typ, otevření složky není karta', () {
    final upload = ClienteAuditEvent(
      id: '1',
      createdAt: DateTime.utc(2026, 9, 12),
      action: 'documentos.insert',
      detail: {
        'tipo': 'dni_nie',
        'original_name': 'nie_petr.pdf',
      },
    );
    expect(upload.documentName, 'nie_petr.pdf');
    expect(upload.documentTipo, 'dni_nie');
    expect(upload.actionI18nKey, 'audit.action.documentos.insert');

    final fileOpen = ClienteAuditEvent(
      id: '2',
      createdAt: DateTime.utc(2026, 9, 12),
      action: 'documentos.open',
      detail: {
        'tipo': 'pasaporte',
        'original_name': 'passport.jpg',
      },
    );
    expect(fileOpen.actionI18nKey, 'audit.action.documentos.open');
    expect(fileOpen.documentName, 'passport.jpg');

    final folder = ClienteAuditEvent(
      id: '3',
      createdAt: DateTime.utc(2026, 9, 12),
      action: 'clientes.open',
      detail: {'surface': 'carpeta'},
    );
    expect(folder.actionI18nKey, 'audit.action.clientes.openCarpeta');

    final card = ClienteAuditEvent(
      id: '4',
      createdAt: DateTime.utc(2026, 9, 12),
      action: 'clientes.open',
      detail: {'surface': 'card'},
    );
    expect(card.actionI18nKey, 'audit.action.clientes.open');
  });
}
