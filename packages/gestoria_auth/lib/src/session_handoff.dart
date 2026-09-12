import 'package:supabase_flutter/supabase_flutter.dart';

/// Hash `#refresh_token=…` → GoTrue [setSession]. Nikdy volat s prázdným tokenem
/// (na webu TypeError, OmniToca).
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

  static String? sessionIdFromUri(Uri uri) {
    final id = uri.queryParameters['session_id']?.trim() ?? '';
    return id.isEmpty ? null : id;
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
    return session;
  }
}
