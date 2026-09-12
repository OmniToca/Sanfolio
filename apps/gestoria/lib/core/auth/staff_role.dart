import 'package:gestoria_auth/gestoria_auth.dart';

/// Role v aktuální kanceláři. Impersonace Supportu = práva ownera.
String? currentOfficeRole(AuthSnapshot snap) {
  if (snap.impersonating) return 'owner';
  final tid = snap.currentTenantId;
  if (tid == null) return null;
  for (final m in snap.memberships) {
    if (m.tenantId == tid) return m.role;
  }
  return null;
}

bool canInviteStaff(AuthSnapshot snap) => currentOfficeRole(snap) == 'owner';

/// Stopa LOPDGDD na kartě: jen owner (impersonace Supportu = owner).
bool canViewClienteAudit(AuthSnapshot snap) =>
    currentOfficeRole(snap) == 'owner';

/// Vysypat originál ze Storage: jen owner (impersonace Supportu = owner).
bool canPurgeDocumento(AuthSnapshot snap) =>
    currentOfficeRole(snap) == 'owner';

/// Asistente spis neschová. Owner, gestor a impersonace ano.
bool canSoftDeleteExpediente(AuthSnapshot snap) {
  final role = currentOfficeRole(snap);
  return role == 'owner' || role == 'gestor';
}
