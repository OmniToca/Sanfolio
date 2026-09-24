import 'package:supabase_flutter/supabase_flutter.dart';

import 'clear_url_fragment.dart';

/// Handoff Support → kancelář: `#code=…` (M6) nebo legacy `#refresh_token=…`.
/// Nikdy volat [establish] s prázdným tokenem (na webu TypeError, OmniToca).
abstract final class SessionHandoff {
  static String? refreshTokenFromUri(Uri uri) {
    final q = uri.queryParameters['refresh_token']?.trim();
    if (q != null && q.isNotEmpty && q != 'null' && q != 'undefined') {
      return q;
    }
    final frag = uri.fragment;
    if (frag.isEmpty || frag.startsWith('/')) return null;
    final params = Uri.splitQueryString(frag.contains('=') ? frag : '');
    final fromFrag = params['refresh_token']?.trim();
    if (fromFrag == null ||
        fromFrag.isEmpty ||
        fromFrag == 'null' ||
        fromFrag == 'undefined') {
      return null;
    }
    return fromFrag;
  }

  /// Jednorázový kód z Edge `impersonation-handoff` (create).
  static String? handoffCodeFromUri(Uri uri) {
    final q = uri.queryParameters['code']?.trim();
    if (q != null && q.isNotEmpty && q != 'null' && q != 'undefined') {
      return q;
    }
    final frag = uri.fragment;
    if (frag.isEmpty || frag.startsWith('/')) return null;
    final params = Uri.splitQueryString(frag.contains('=') ? frag : '');
    final fromFrag = params['code']?.trim();
    if (fromFrag == null ||
        fromFrag.isEmpty ||
        fromFrag == 'null' ||
        fromFrag == 'undefined') {
      return null;
    }
    return fromFrag;
  }

  static String? sessionIdFromUri(Uri uri) {
    final id = uri.queryParameters['session_id']?.trim() ?? '';
    return id.isEmpty ? null : id;
  }

  /// Vymění handoff code za refresh_token (service path na Edge).
  static Future<String> redeemHandoffCode({
    required SupabaseClient client,
    required String sessionId,
    required String code,
  }) async {
    final response = await client.functions.invoke(
      'impersonation-handoff',
      body: {
        'action': 'redeem',
        'session_id': sessionId,
        'code': code,
      },
    );
    final data = response.data;
    if (data is! Map || data['ok'] != true) {
      final err = data is Map ? data['error'] : response.status;
      throw StateError('handoff redeem failed: $err');
    }
    final token = '${data['refresh_token'] ?? ''}'.trim();
    if (token.isEmpty || token == 'null' || token == 'undefined') {
      throw const FormatException('handoff returned empty refresh_token');
    }
    return token;
  }

  static Future<Session> establish(GoTrueClient auth, String refreshToken) async {
    final token = refreshToken.trim();
    if (token.isEmpty || token == 'null' || token == 'undefined') {
      throw const FormatException('refresh_token is empty');
    }
    final response = await auth.setSession(token);
    final session = response.session;
    if (session == null) {
      throw const FormatException('setSession returned a null session');
    }
    if (session.accessToken.trim().isEmpty) {
      throw const FormatException('setSession returned an empty access token');
    }
    // Proč: token/code v hash nesmí zůstat v historii / screen share.
    clearUrlFragment();
    return session;
  }
}
