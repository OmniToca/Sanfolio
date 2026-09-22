import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/settings/office_team_controller.dart';

void main() {
  test('invite chyba z Edge je kód, ne plaintext API', () {
    expect(inviteStaffErrorCode('team_full'), 'team_full');
    expect(inviteStaffErrorCode({'error': 'already_member'}), 'already_member');
    expect(
      inviteStaffErrorCode(
        'FunctionException(status: 500)',
        fallback: 'A user with this email address has already been registered',
      ),
      'already_registered',
    );
    expect(inviteStaffErrorCode('nope'), 'invite_error');
    expect(
      inviteStaffErrorCode('redirect_uri is not allowed'),
      'invite_redirect',
    );
  });
}
