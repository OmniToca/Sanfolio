import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

class GestoriaRoot extends StatelessWidget {
  const GestoriaRoot({super.key, this.overrides = const []});

  final List<Override> overrides;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(overrides: overrides, child: const GestoriaApp());
  }
}

class GestoriaApp extends ConsumerWidget {
  const GestoriaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    ref.listen(authControllerProvider, (prev, next) {
      final code = next.valueOrNull?.profile?.locale ?? 'cs';
      final loc = Locale(code);
      if (!context.supportedLocales.contains(loc)) return;
      if (context.locale == loc) return;
      context.setLocale(loc);
    });
    return MaterialApp.router(
      title: 'app.title'.tr(),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      routerConfig: router,
    );
  }
}
