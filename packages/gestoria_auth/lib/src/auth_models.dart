class StaffProfile {
  const StaffProfile({
    required this.id,
    required this.email,
    required this.isSupport,
    this.fullName,
    this.locale = 'cs',
  });

  final String id;
  final String email;
  final bool isSupport;
  final String? fullName;
  /// Jazyk UI kanceláře. Není to `clientes.locale`.
  final String locale;
}

class OfficeMembership {
  const OfficeMembership({
    required this.tenantId,
    required this.role,
    required this.officeName,
  });

  final String tenantId;
  final String role;
  final String officeName;
}

class ImpersonationSession {
  const ImpersonationSession({
    required this.sessionId,
    required this.tenantId,
    required this.officeName,
    required this.accessReason,
    required this.expiresAt,
  });

  final String sessionId;
  final String tenantId;
  final String officeName;
  final String accessReason;
  final DateTime expiresAt;
}

class AuthSnapshot {
  const AuthSnapshot({
    this.configured = true,
    this.loading = false,
    this.sessionPresent = false,
    this.profile,
    this.memberships = const [],
    this.impersonation,
    this.licenceBlocked = false,
    this.passwordRecovery = false,
    this.error,
  });

  final bool configured;
  final bool loading;
  final bool sessionPresent;
  final StaffProfile? profile;
  final List<OfficeMembership> memberships;
  final ImpersonationSession? impersonation;
  final bool licenceBlocked;
  /// Session z odkazu „reset hesla“. Inbox až po uložení nového hesla.
  final bool passwordRecovery;
  final String? error;

  bool get signedIn => sessionPresent && profile != null;
  bool get isSupport => profile?.isSupport == true;
  bool get impersonating => impersonation != null;

  /// Tenant, se kterým UI pracuje: impersonace, jinak první členství.
  String? get currentTenantId {
    final fromImpersonation = impersonation?.tenantId.trim();
    if (fromImpersonation != null && fromImpersonation.isNotEmpty) {
      return fromImpersonation;
    }
    if (memberships.isEmpty) return null;
    final fromMember = memberships.first.tenantId.trim();
    return fromMember.isEmpty ? null : fromMember;
  }

  static const signedOut = AuthSnapshot();
  static const unconfigured = AuthSnapshot(configured: false);
}
