import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:gestoria_os/core/auth/staff_role.dart';
import 'package:gestoria_os/features/clientes/cliente_audit.dart';

void main() {
  const owner = AuthSnapshot(
    sessionPresent: true,
    memberships: [
      OfficeMembership(tenantId: 't1', role: 'owner', officeName: 'Test'),
    ],
  );
  const gestor = AuthSnapshot(
    sessionPresent: true,
    memberships: [
      OfficeMembership(tenantId: 't1', role: 'gestor', officeName: 'Test'),
    ],
  );
  const asistente = AuthSnapshot(
    sessionPresent: true,
    memberships: [
      OfficeMembership(tenantId: 't1', role: 'asistente', officeName: 'Test'),
    ],
  );

  test('owner zve kolegy, asistente neschová spis', () {
    expect(canInviteStaff(owner), isTrue);
    expect(canInviteStaff(gestor), isFalse);
    expect(canSoftDeleteExpediente(owner), isTrue);
    expect(canSoftDeleteExpediente(gestor), isTrue);
    expect(canSoftDeleteExpediente(asistente), isFalse);
  });

  test('audit karty vidí jen owner, ne gestor ani asistente', () {
    expect(canViewClienteAudit(owner), isTrue);
    expect(canViewClienteAudit(gestor), isFalse);
    expect(canViewClienteAudit(asistente), isFalse);
    expect(ClienteAuditEvent(
      id: '1',
      createdAt: DateTime.utc(2026, 9, 12),
      action: 'clientes.open',
    ).actionI18nKey, 'audit.action.clientes.open');
  });
}
