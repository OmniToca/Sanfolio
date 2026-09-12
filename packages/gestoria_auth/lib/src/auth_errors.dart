/// Mapování GoTrue hlášek na i18n klíče. Do UI nepatří plaintext z API.
String authErrorI18nKey(String message) {
  final m = message.toLowerCase();
  if (m.contains('invalid login') ||
      m.contains('invalid_credentials') ||
      m.contains('invalid credentials')) {
    return 'auth.invalidCredentials';
  }
  if (m.contains('email not confirmed') || m.contains('not confirmed')) {
    return 'auth.emailNotConfirmed';
  }
  if (m.contains('user not found')) {
    return 'auth.invalidCredentials';
  }
  return 'auth.signInError';
}

/// Recovery token z e-mailu. `/reset-password` samotné session nenese.
bool looksLikePasswordRecovery(Uri uri) {
  if (uri.queryParameters['type'] == 'recovery') return true;
  final frag = uri.fragment;
  if (frag.contains('type=recovery')) return true;
  final q = uri.query.toLowerCase();
  return q.contains('type=recovery');
}
