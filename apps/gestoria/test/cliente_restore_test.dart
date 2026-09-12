import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:gestoria_os/features/clientes/clientes_providers.dart';

void main() {
  test('owner a impersonace smí obnovit, gestor ne', () {
    const owner = AuthSnapshot(
      sessionPresent: true,
      memberships: [
        OfficeMembership(
          tenantId: 't1',
          role: 'owner',
          officeName: 'Test',
        ),
      ],
    );
    const gestor = AuthSnapshot(
      sessionPresent: true,
      memberships: [
        OfficeMembership(
          tenantId: 't1',
          role: 'gestor',
          officeName: 'Test',
        ),
      ],
    );
    final support = AuthSnapshot(
      sessionPresent: true,
      impersonation: ImpersonationSession(
        sessionId: 's',
        tenantId: 't1',
        officeName: 'Test',
        accessReason: 'check',
        expiresAt: DateTime.utc(2030),
      ),
    );
    expect(canRestoreDeleted(owner), isTrue);
    expect(canRestoreDeleted(gestor), isFalse);
    expect(canRestoreDeleted(support), isTrue);
  });
}
