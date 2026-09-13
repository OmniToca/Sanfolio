/// Kontrola změny hesla před GoTrue. Do UI jdou jen i18n klíče.
enum PasswordChangeIssue {
  none,
  currentEmpty,
  tooShort,
  mismatch,
  unchanged,
}

PasswordChangeIssue passwordChangeIssue({
  required String current,
  required String next,
  required String confirm,
}) {
  if (current.isEmpty) return PasswordChangeIssue.currentEmpty;
  if (next.length < 8) return PasswordChangeIssue.tooShort;
  if (next != confirm) return PasswordChangeIssue.mismatch;
  if (current == next) return PasswordChangeIssue.unchanged;
  return PasswordChangeIssue.none;
}

String passwordChangeI18nKey(PasswordChangeIssue issue) {
  return switch (issue) {
    PasswordChangeIssue.none => '',
    PasswordChangeIssue.currentEmpty => 'auth.currentPasswordRequired',
    PasswordChangeIssue.tooShort => 'auth.passwordTooShort',
    PasswordChangeIssue.mismatch => 'auth.passwordMismatch',
    PasswordChangeIssue.unchanged => 'auth.passwordUnchanged',
  };
}
