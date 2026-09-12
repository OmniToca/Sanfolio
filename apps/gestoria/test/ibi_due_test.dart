import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/settings/office_settings_controller.dart';

void main() {
  test('IBI splatnost není 1. 11., dokud kancelář nenastaví měsíc a den', () {
    expect(const OfficeSettings().ibiDueConfigured, isFalse);
    expect(
      const OfficeSettings(ibiDueMonth: 11, ibiDueDay: 1).ibiDueConfigured,
      isTrue,
    );
    expect(
      OfficeSettings.fromRow({'ibi_due_month': null, 'ibi_due_day': null})
          .ibiDueConfigured,
      isFalse,
    );
  });
}
