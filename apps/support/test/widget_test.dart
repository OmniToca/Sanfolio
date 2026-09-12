import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gestoria_support/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('Unauthenticated Support shows login', (tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('cs')],
        path: 'assets/translations',
        fallbackLocale: const Locale('cs'),
        startLocale: const Locale('cs'),
        child: const SupportRoot(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Přihlásit'), findsWidgets);
  });
}
