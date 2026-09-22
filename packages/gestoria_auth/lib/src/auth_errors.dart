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

/// GoTrue už heslo zapsalo; druhý klik tváří „nejde uložit“.
bool authPasswordAlreadyApplied(String message) {
  final m = message.toLowerCase();
  return m.contains('should be different') ||
      m.contains('same as the old') ||
      m.contains('same password') ||
      m.contains('different from the old');
}

/// Odkaz z e-mailu, který musí nejdřív nastavit heslo. Samotné `/reset-password`
/// session nenese. Invite má `type=invite`, ne `recovery` — jinak inbox bez hesla.
bool looksLikePasswordRecovery(Uri uri) {
  final type = (uri.queryParameters['type'] ?? _fragmentParam(uri, 'type'))
      ?.trim()
      .toLowerCase();
  if (type == 'recovery' || type == 'invite' || type == 'signup') {
    return true;
  }
  // PKCE: GoTrue často pošle jen `?code=`, bez `type=`.
  if (uri.queryParameters['code']?.isNotEmpty == true) return true;
  return _fragmentParam(uri, 'code') != null;
}

String? _fragmentParam(Uri uri, String key) {
  var frag = uri.fragment;
  if (frag.isEmpty) return null;
  if (frag.startsWith('/')) {
    final i = frag.indexOf('?');
    if (i < 0) return null;
    frag = frag.substring(i + 1);
  }
  if (!frag.contains('=')) return null;
  final v = Uri.splitQueryString(frag)[key]?.trim();
  return (v == null || v.isEmpty) ? null : v;
}
