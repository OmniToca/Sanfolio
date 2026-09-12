import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await bootstrapSupabase();
  runApp(
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
      child: const GestoriaRoot(),
    ),
  );
}
