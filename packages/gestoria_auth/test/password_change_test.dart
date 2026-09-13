import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

void main() {
  test('změna hesla chce současné, osm znaků a jiné nové', () {
    expect(
      passwordChangeIssue(current: '', next: 'abcdefgh', confirm: 'abcdefgh'),
      PasswordChangeIssue.currentEmpty,
    );
    expect(
      passwordChangeIssue(current: 'old', next: 'short', confirm: 'short'),
      PasswordChangeIssue.tooShort,
    );
    expect(
      passwordChangeIssue(
        current: 'old-password',
        next: 'new-password',
        confirm: 'other',
      ),
      PasswordChangeIssue.mismatch,
    );
    expect(
      passwordChangeIssue(
        current: 'samepass1',
        next: 'samepass1',
        confirm: 'samepass1',
      ),
      PasswordChangeIssue.unchanged,
    );
    expect(
      passwordChangeIssue(
        current: 'old-password',
        next: 'new-password',
        confirm: 'new-password',
      ),
      PasswordChangeIssue.none,
    );
    expect(
      passwordChangeI18nKey(PasswordChangeIssue.mismatch),
      'auth.passwordMismatch',
    );
  });
}
