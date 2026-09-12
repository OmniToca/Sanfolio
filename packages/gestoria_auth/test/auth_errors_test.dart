import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

void main() {
  test('invalid login maps to i18n, not API English', () {
    expect(
      authErrorI18nKey('Invalid login credentials'),
      'auth.invalidCredentials',
    );
    expect(
      authErrorI18nKey('invalid_credentials'),
      'auth.invalidCredentials',
    );
  });

  test('recovery URL is the token in hash, not the route itself', () {
    expect(
      looksLikePasswordRecovery(
        Uri.parse('http://localhost:5555/#/reset-password'),
      ),
      isFalse,
    );
    expect(
      looksLikePasswordRecovery(
        Uri.parse(
          'http://localhost:5555/#access_token=abc&type=recovery&refresh_token=x',
        ),
      ),
      isTrue,
    );
    expect(
      looksLikePasswordRecovery(
        Uri.parse('http://localhost:5555/?type=recovery&code=pkce'),
      ),
      isTrue,
    );
  });

  test('password reset redirect stays on origin query, not behind hash', () {
    expect(PortalUrls.gestoriaPasswordResetRedirect(), 'http://localhost:5555');
    expect(PortalUrls.gestoriaPasswordResetRedirect().contains('#'), isFalse);
  });
}
