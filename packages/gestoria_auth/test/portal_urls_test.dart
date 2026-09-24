import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

void main() {
  test('impersonation URI puts session_id in query and code in hash', () {
    final uri = PortalUrls.gestoriaImpersonationAccept(
      sessionId: 'sess-1',
      handoffCode: 'abc123deadbeef',
    );
    expect(uri.path, endsWith('/impersonation/accept'));
    expect(uri.queryParameters['session_id'], 'sess-1');
    expect(uri.queryParameters.containsKey('code'), isFalse);
    expect(uri.queryParameters.containsKey('refresh_token'), isFalse);
    expect(uri.fragment, contains('code='));
    expect(uri.fragment, isNot(contains('refresh_token=')));
    expect(SessionHandoff.handoffCodeFromUri(uri), 'abc123deadbeef');
    expect(SessionHandoff.refreshTokenFromUri(uri), isNull);
    expect(SessionHandoff.sessionIdFromUri(uri), 'sess-1');
  });

  test('legacy refresh_token in hash still parses', () {
    final uri = PortalUrls.gestoriaImpersonationAccept(
      sessionId: 'sess-1',
      refreshToken: 'refresh/token+value',
    );
    expect(uri.fragment, contains('refresh_token='));
    expect(SessionHandoff.refreshTokenFromUri(uri), 'refresh/token+value');
    expect(SessionHandoff.handoffCodeFromUri(uri), isNull);
  });

  test('empty or null-literal handoff secrets are rejected', () {
    expect(SessionHandoff.refreshTokenFromUri(Uri.parse('/x')), isNull);
    expect(SessionHandoff.handoffCodeFromUri(Uri.parse('/x')), isNull);
    expect(
      SessionHandoff.refreshTokenFromUri(
        Uri.parse('/impersonation/accept?session_id=a#refresh_token=null'),
      ),
      isNull,
    );
    expect(
      SessionHandoff.handoffCodeFromUri(
        Uri.parse('/impersonation/accept?session_id=a#code=null'),
      ),
      isNull,
    );
  });
}
