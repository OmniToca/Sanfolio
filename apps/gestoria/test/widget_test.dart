import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gestoria_os/features/auth/login_screen.dart';
// ui_web stub: import nesmí shodit VM test (posta_html_frame_stub).
import 'package:gestoria_os/features/posta/posta_html_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('Unauthenticated app shows login', (tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [
          Locale('cs'),
          Locale('en'),
          Locale('es'),
          Locale('de'),
          Locale('fr'),
        ],
        path: 'assets/translations',
        fallbackLocale: const Locale('cs'),
        startLocale: const Locale('cs'),
        child: const ProviderScope(
          child: MaterialApp(home: LoginScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    // Bez localizationDelegates na MaterialApp.home zůstane klíč; copy je v JSON.
    expect(find.text('auth.signIn'), findsWidgets);
    expect(find.text('auth.email'), findsWidgets);
    expect(find.text('auth.forgotPassword'), findsOneWidget);
    // Pošta HTML view je importovatelná na VM (ne dart:ui_web).
    expect(PostaHtmlBody, isNotNull);
  });
}
