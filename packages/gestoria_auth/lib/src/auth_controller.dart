import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_errors.dart';
import 'auth_models.dart';
import 'open_external_url.dart';
import 'password_change.dart';
import 'portal_urls.dart';
import 'supabase_bootstrap.dart';

/// Stav přihlášení. Proč skip prvního auth eventu: jinak `invalidateSelf` smyčka.
class AuthController extends AsyncNotifier<AuthSnapshot> {
  var _passwordRecovery = false;

  @override
  Future<AuthSnapshot> build() async {
    if (!SupabaseConfig.isConfigured) {
      return AuthSnapshot.unconfigured;
    }
    final client = trySupabaseClient();
    if (client == null) {
      return AuthSnapshot.unconfigured;
    }
    var primed = false;
    final sub = client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _passwordRecovery = true;
      }
      if (!primed) {
        primed = true;
        // První event jinak skip — recovery ale musí hydrate znovu.
        if (data.event != AuthChangeEvent.passwordRecovery) {
          return;
        }
      }
      ref.invalidateSelf();
    });
    ref.onDispose(sub.cancel);
    return _hydrate(client);
  }

  Future<void> signIn(String email, String password) async {
    final client = trySupabaseClient();
    if (client == null) {
      state = const AsyncData(AuthSnapshot.unconfigured);
      return;
    }
    state = const AsyncLoading();
    try {
      await client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e, st) {
      state = AsyncError(e, st);
      state = AsyncData(
        AuthSnapshot(error: authErrorI18nKey(e.message), configured: true),
      );
    }
  }

  /// E-mail s odkazem. Stejná hláška, ať účet existuje nebo ne (žádný leak).
  Future<void> requestPasswordReset(String email) async {
    final client = trySupabaseClient();
    if (client == null) {
      throw StateError('not configured');
    }
    final trimmed = email.trim();
    if (trimmed.isEmpty || !trimmed.contains('@')) {
      throw ArgumentError('email');
    }
    await client.auth.resetPasswordForEmail(
      trimmed,
      redirectTo: PortalUrls.gestoriaPasswordResetRedirect(),
    );
  }

  Future<void> updatePassword(String password) async {
    final client = trySupabaseClient();
    if (client == null) {
      throw StateError('not configured');
    }
    await client.auth.updateUser(UserAttributes(password: password));
    _passwordRecovery = false;
    ref.invalidateSelf();
  }

  /// Přihlášený člověk. Nejdřív ověří současné heslo, teprve pak zapíše nové.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final issue = passwordChangeIssue(
      current: currentPassword,
      next: newPassword,
      confirm: newPassword,
    );
    if (issue != PasswordChangeIssue.none) {
      throw ArgumentError(passwordChangeI18nKey(issue));
    }
    final client = trySupabaseClient();
    final email = client?.auth.currentUser?.email?.trim() ?? '';
    if (client == null || email.isEmpty) {
      throw StateError('not configured');
    }
    await client.auth.signInWithPassword(
      email: email,
      password: currentPassword,
    );
    await client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> signOut() async {
    final client = trySupabaseClient();
    await client?.auth.signOut();
    _passwordRecovery = false;
    state = const AsyncData(AuthSnapshot.signedOut);
  }

  Future<String> createOffice({
    required String name,
    required String ownerEmail,
    String? displayName,
  }) async {
    final client = trySupabaseClient();
    if (client == null) {
      throw StateError('Supabase is not configured');
    }
    final response = await client.functions.invoke(
      'create-office',
      body: {
        'name': name,
        'owner_email': ownerEmail,
        'display_name': displayName ?? name,
      },
    );
    final data = response.data;
    if (data is! Map || data['ok'] != true) {
      final err = data is Map ? data['error'] : response.status;
      throw StateError('$err');
    }
    return '${data['tenant_id']}';
  }

  /// INSERT session + stejná záložka na kancelář s refresh_token v hash.
  Future<void> startImpersonation({
    required String tenantId,
    required String reason,
    String note = '',
  }) async {
    final client = trySupabaseClient();
    if (client == null) {
      throw StateError('Supabase is not configured');
    }
    final refresh = client.auth.currentSession?.refreshToken?.trim();
    if (refresh == null || refresh.isEmpty) {
      throw StateError('Missing refresh_token — cannot hand off');
    }
    final sessionId = await client.rpc<dynamic>(
      'start_impersonation',
      params: {
        'p_tenant_id': tenantId,
        'p_reason': reason,
        'p_note': note,
      },
    );
    final id = '$sessionId'.trim();
    if (id.isEmpty || id == 'null') {
      throw StateError('start_impersonation returned no id');
    }
    final uri = PortalUrls.gestoriaImpersonationAccept(
      sessionId: id,
      refreshToken: refresh,
    );
    assignAppUrl(uri.toString());
  }

  Future<void> endImpersonationAndReturnToSupport() async {
    final client = trySupabaseClient();
    final sessionId = state.valueOrNull?.impersonation?.sessionId;
    if (client != null && sessionId != null) {
      await client.rpc(
        'end_impersonation',
        params: {'p_session_id': sessionId},
      );
    }
    assignAppUrl(PortalUrls.supportAppBase());
  }

  /// Jazyk UI tohoto člověka. Tenant `staff_locale` je jen fallback v DB.
  Future<void> setStaffLocale(String locale) async {
    final client = trySupabaseClient();
    final uid = client?.auth.currentUser?.id;
    final code = _staffLocale(locale);
    if (client == null || uid == null) return;
    await client.from('profiles').update({'locale': code}).eq('id', uid);
    ref.invalidateSelf();
  }

  Future<AuthSnapshot> _hydrate(SupabaseClient client) async {
    final session = client.auth.currentSession;
    if (session == null) {
      return AuthSnapshot.signedOut;
    }
    try {
      final uid = session.user.id;
      final profileRow = await client
          .from('profiles')
          .select('id, email, full_name, is_support, locale')
          .eq('id', uid)
          .maybeSingle();
      if (profileRow == null) {
        return AuthSnapshot(
          sessionPresent: true,
          error: 'profile missing',
        );
      }
      final profile = StaffProfile(
        id: '${profileRow['id']}',
        email: '${profileRow['email'] ?? ''}',
        isSupport: profileRow['is_support'] == true,
        fullName: profileRow['full_name'] as String?,
        locale: _staffLocale(profileRow['locale']),
      );

      final memberRows = await client
          .from('tenant_members')
          .select('tenant_id, role, tenants(name)')
          .eq('profile_id', uid)
          .isFilter('deleted_at', null);

      final memberships = <OfficeMembership>[];
      for (final raw in memberRows as List) {
        if (raw is! Map) continue;
        final tenants = raw['tenants'];
        var name = '';
        if (tenants is Map) {
          name = '${tenants['name'] ?? ''}'.trim();
        }
        memberships.add(
          OfficeMembership(
            tenantId: '${raw['tenant_id']}',
            role: '${raw['role']}',
            officeName: name,
          ),
        );
      }

      ImpersonationSession? impersonation;
      if (profile.isSupport) {
        final rows = await client.rpc('current_impersonation');
        if (rows is List && rows.isNotEmpty && rows.first is Map) {
          final m = Map<String, dynamic>.from(rows.first as Map);
          impersonation = ImpersonationSession(
            sessionId: '${m['session_id']}',
            tenantId: '${m['tenant_id']}',
            officeName: '${m['display_name'] ?? m['tenant_name'] ?? ''}',
            accessReason: '${m['access_reason'] ?? ''}',
            expiresAt: DateTime.parse('${m['expires_at']}'),
          );
        }
      }

      var licenceBlocked = false;
      if (!profile.isSupport && memberships.isNotEmpty) {
        final tenantId = memberships.first.tenantId;
        final mods = await client
            .from('organization_modules')
            .select('status')
            .eq('tenant_id', tenantId)
            .isFilter('deleted_at', null);
        final list = mods as List;
        licenceBlocked = list.any((row) {
          if (row is! Map) return false;
          final s = '${row['status']}';
          return s == 'cancelled' || s == 'past_due';
        });
      }

      return AuthSnapshot(
        sessionPresent: true,
        profile: profile,
        memberships: memberships,
        impersonation: impersonation,
        licenceBlocked: licenceBlocked,
        passwordRecovery:
            _passwordRecovery || looksLikePasswordRecovery(Uri.base),
      );
    } on Object catch (e, st) {
      debugPrint('auth hydrate failed: $e\n$st');
      return AuthSnapshot(sessionPresent: true, error: e.toString());
    }
  }
}

String _staffLocale(Object? value) {
  const allowed = {'cs', 'en', 'es', 'de', 'fr'};
  final code = '$value'.trim();
  return allowed.contains(code) ? code : 'cs';
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSnapshot>(AuthController.new);

/// Pro GoRouter refreshListenable.
class AuthRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

final authRefreshProvider = ChangeNotifierProvider<AuthRefresh>((ref) {
  final notifier = AuthRefresh();
  ref.listen(authControllerProvider, (previous, next) => notifier.ping());
  return notifier;
});
