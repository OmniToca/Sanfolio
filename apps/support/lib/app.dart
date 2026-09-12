import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

class SupportRoot extends StatelessWidget {
  const SupportRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderScope(child: SupportApp());
  }
}

class SupportApp extends ConsumerWidget {
  const SupportApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
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
