import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../ai/ai_sheet.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _paths = ['/inbox', '/clientes', '/settings'];

  int _indexFor(String location) {
    if (location.startsWith('/settings')) return 2;
    if (location.startsWith('/clientes')) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final selected = _indexFor(location);
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final impersonation =
        ref.watch(authControllerProvider).valueOrNull?.impersonation;

    void goIndex(int i) => context.go(_paths[i]);

    final destinations = [
      NavigationDestination(
        icon: const Icon(Icons.inbox_outlined),
        selectedIcon: const Icon(Icons.inbox),
        label: 'nav.inbox'.tr(),
      ),
      NavigationDestination(
        icon: const Icon(Icons.people_outline),
        selectedIcon: const Icon(Icons.people),
        label: 'nav.clients'.tr(),
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: 'nav.settings'.tr(),
      ),
    ];

    final banner = impersonation == null
        ? null
        : MaterialBanner(
            content: Text(
              'impersonation.banner'.tr(
                namedArgs: {'office': impersonation.officeName},
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => ref
                    .read(authControllerProvider.notifier)
                    .endImpersonationAndReturnToSupport(),
                child: Text('impersonation.end'.tr()),
              ),
            ],
          );

    Widget withBanner(Widget body) {
      if (banner == null) return body;
      return Column(
        children: [
          banner,
          Expanded(child: body),
        ],
      );
    }

    Widget fab() => FeatureGate(
          module: GestoriaModule.aiCopilot,
          child: FloatingActionButton(
            tooltip: 'ai.title'.tr(),
            onPressed: () => openAiSheet(context, ref),
            child: const Icon(Icons.auto_awesome),
          ),
        );

    if (!wide) {
      return Scaffold(
        body: withBanner(child),
        floatingActionButton: fab(),
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: goIndex,
          destinations: destinations,
        ),
      );
    }

    return Scaffold(
      floatingActionButton: fab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      body: withBanner(
        Row(
          children: [
            NavigationRail(
              selectedIndex: selected,
              onDestinationSelected: goIndex,
              labelType: NavigationRailLabelType.all,
              destinations: [
                NavigationRailDestination(
                  icon: const Icon(Icons.inbox_outlined),
                  selectedIcon: const Icon(Icons.inbox),
                  label: Text('nav.inbox'.tr()),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.people_outline),
                  selectedIcon: const Icon(Icons.people),
                  label: Text('nav.clients'.tr()),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings),
                  label: Text('nav.settings'.tr()),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
