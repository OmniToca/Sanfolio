import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

void main() {
  test('impersonation URI puts session_id in query and refresh_token in hash', () {
    final uri = PortalUrls.gestoriaImpersonationAccept(
      sessionId: 'sess-1',
      refreshToken: 'refresh/token+value',
    );
    expect(uri.path, endsWith('/impersonation/accept'));
    expect(uri.queryParameters['session_id'], 'sess-1');
    expect(uri.queryParameters.containsKey('refresh_token'), isFalse);
    expect(uri.fragment, contains('refresh_token='));
    expect(SessionHandoff.refreshTokenFromUri(uri), 'refresh/token+value');
    expect(SessionHandoff.sessionIdFromUri(uri), 'sess-1');
  });

  test('empty or null-literal refresh_token is rejected', () {
    expect(SessionHandoff.refreshTokenFromUri(Uri.parse('/x')), isNull);
    expect(
      SessionHandoff.refreshTokenFromUri(
        Uri.parse('/impersonation/accept?session_id=a#refresh_token=null'),
      ),
      isNull,
    );
  });
}
