import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

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

  Future<void> invite({required String email, required String role}) async {
    final auth = ref.read(authControllerProvider).valueOrNull;
    final tenantId = auth?.currentTenantId;
    final client = trySupabaseClient();
    if (auth == null || tenantId == null || client == null) {
      throw StateError('not configured');
    }
    if (!canInviteStaff(auth)) {
      throw StateError('owner only');
    }
    final response = await client.functions.invoke(
      'invite-staff',
      body: {
        'tenant_id': tenantId,
        'email': email.trim().toLowerCase(),
        'role': role,
      },
    );
    final data = response.data;
    if (data is! Map || data['ok'] != true) {
      final err = data is Map ? '${data['error']}' : '${response.status}';
      throw StateError(err);
    }
    ref.invalidateSelf();
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
}

final officeTeamProvider =
    AsyncNotifierProvider<OfficeTeamController, List<OfficeMember>>(
  OfficeTeamController.new,
);

const officeTeamLimit = 3;
