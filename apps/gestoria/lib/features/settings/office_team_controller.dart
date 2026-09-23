import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/auth/staff_access.dart';
import '../../core/auth/staff_role.dart';

class OfficeMember {
  const OfficeMember({
    required this.id,
    required this.profileId,
    required this.email,
    required this.role,
    this.fullName,
  });

  final String id;
  final String profileId;
  final String email;
  final String role;
  final String? fullName;
}

/// Tým kanceláře. Zve jen owner přes Edge Function.
class OfficeTeamController extends AsyncNotifier<List<OfficeMember>> {
  @override
  Future<List<OfficeMember>> build() async {
    ref.watch(authControllerProvider);
    final auth = await ref.watch(authControllerProvider.future);
    final tenantId = auth.currentTenantId;
    final client = trySupabaseClient();
    if (tenantId == null || client == null) return [];
    final rows = await client
        .from('tenant_members')
        .select('id, profile_id, role, profiles(email, full_name)')
        .eq('tenant_id', tenantId)
        .isFilter('deleted_at', null)
        .order('created_at');
    final out = <OfficeMember>[];
    for (final raw in rows as List) {
      if (raw is! Map) continue;
      final profiles = raw['profiles'];
      var email = '';
      String? name;
      if (profiles is Map) {
        email = '${profiles['email'] ?? ''}'.trim();
        final n = '${profiles['full_name'] ?? ''}'.trim();
        name = n.isEmpty ? null : n;
      }
      out.add(
        OfficeMember(
          id: '${raw['id']}',
          profileId: '${raw['profile_id']}',
          email: email,
          role: '${raw['role']}',
          fullName: name,
        ),
      );
    }
    return out;
  }

  Future<OfficeInviteKind> invite({
    required String email,
    required String role,
  }) async {
    final auth = ref.read(authControllerProvider).valueOrNull;
    final tenantId = auth?.currentTenantId;
    final client = trySupabaseClient();
    if (auth == null || tenantId == null || client == null) {
      throw StateError('not configured');
    }
    if (!canInviteStaff(auth)) {
      throw StateError('owner only');
    }
    late final dynamic response;
    try {
      response = await client.functions.invoke(
        'invite-staff',
        body: {
          'tenant_id': tenantId,
          'email': email.trim().toLowerCase(),
          'role': role,
        },
      );
    } on Object catch (e) {
      throw StateError(inviteStaffErrorCode(e));
    }
    final data = response.data;
    if (data is! Map || data['ok'] != true) {
      throw StateError(inviteStaffErrorCode(data, fallback: response.status));
    }
    ref.invalidateSelf();
    if (data['existing'] == true) return OfficeInviteKind.existing;
    if (data['email_sent'] == false) return OfficeInviteKind.noEmail;
    return OfficeInviteKind.sent;
  }

  Future<void> removeMember(String memberId) async {
    final auth = ref.read(authControllerProvider).valueOrNull;
    final tenantId = auth?.currentTenantId;
    final client = trySupabaseClient();
    if (auth == null || tenantId == null || client == null) return;
    if (!canInviteStaff(auth)) return;
    final current = state.valueOrNull ?? [];
    OfficeMember? row;
    for (final m in current) {
      if (m.id == memberId) row = m;
    }
    if (row == null || row.role == 'owner') return;
    await client.from('tenant_members').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', memberId).eq('tenant_id', tenantId);
    ref.invalidateSelf();
  }

  Future<StaffAccessScope> loadScope(String profileId) async {
    final auth = ref.read(authControllerProvider).valueOrNull;
    final tenantId = auth?.currentTenantId;
    final client = trySupabaseClient();
    if (tenantId == null || client == null) return StaffAccessScope.open;
    final scopeRow = await client
        .from('staff_scopes')
        .select('scoped, bloque_keys')
        .eq('tenant_id', tenantId)
        .eq('profile_id', profileId)
        .isFilter('deleted_at', null)
        .maybeSingle();
    final accessRows = await client
        .from('staff_cliente_access')
        .select('cliente_id')
        .eq('tenant_id', tenantId)
        .eq('profile_id', profileId)
        .isFilter('deleted_at', null);
    final ids = <String>[];
    for (final raw in accessRows as List) {
      if (raw is! Map) continue;
      final id = '${raw['cliente_id'] ?? ''}'.trim();
      if (id.isNotEmpty) ids.add(id);
    }
    final keys = <String>[];
    final rawKeys = scopeRow?['bloque_keys'];
    if (rawKeys is List) {
      for (final k in rawKeys) {
        final s = '$k'.trim();
        if (s.isNotEmpty) keys.add(s);
      }
    }
    return StaffAccessScope(
      scoped: scopeRow?['scoped'] == true,
      bloqueKeys: keys,
      clienteIds: ids,
    );
  }

  Future<void> saveScope({
    required String profileId,
    required StaffAccessScope scope,
  }) async {
    final client = trySupabaseClient();
    if (client == null) throw StateError('not configured');
    await client.rpc(
      'staff_scope_set',
      params: {
        'p_profile_id': profileId,
        'p_scoped': scope.scoped,
        'p_bloque_keys': scope.bloqueKeys,
        'p_cliente_ids': scope.clienteIds,
      },
    );
  }
}

final officeTeamProvider =
    AsyncNotifierProvider<OfficeTeamController, List<OfficeMember>>(
  OfficeTeamController.new,
);

final myStaffScopeProvider = FutureProvider<StaffAccessScope>((ref) async {
  final auth = await ref.watch(authControllerProvider.future);
  if (auth.impersonating || currentOfficeRole(auth) == 'owner') {
    return StaffAccessScope.open;
  }
  final id = auth.profile?.id;
  if (id == null || id.isEmpty) return StaffAccessScope.open;
  return ref.read(officeTeamProvider.notifier).loadScope(id);
});

/// Výsledek Pozvat. UI mapuje na i18n, ne plaintext z API.
enum OfficeInviteKind { sent, existing, noEmail }

/// Kód z Edge / FunctionException. UI mapuje na i18n, ne plaintext z API.
String inviteStaffErrorCode(Object error, {Object? fallback}) {
  final parts = <String>['$error'];
  if (fallback != null) parts.add('$fallback');
  try {
    final details = (error as dynamic).details;
    parts.add('$details');
    if (details is Map) {
      parts.add('${details['error']}');
      parts.add('${details['message']}');
    }
  } on Object {
    // Bez details stačí toString.
  }
  if (error is Map) {
    parts.add('${error['error']}');
  }
  final blob = parts.join(' ').toLowerCase();
  if (blob.contains('team_full')) return 'team_full';
  if (blob.contains('already_member')) return 'already_member';
  if (blob.contains('already been registered') ||
      blob.contains('already registered')) {
    return 'already_registered';
  }
  if (blob.contains('redirect') || blob.contains('redirect_to')) {
    return 'invite_redirect';
  }
  return 'invite_error';
}
