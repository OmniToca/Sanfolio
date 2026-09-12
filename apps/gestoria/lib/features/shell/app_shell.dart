import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/theme/app_theme.dart';
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
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: goIndex,
          destinations: destinations,
        ),
      );
    }

    return Scaffold(
      floatingActionButton: fab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: withBanner(
        Row(
          children: [
            _OfficeRail(selected: selected, onSelect: goIndex),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// Levý pruh. Tmavý kvůli kontrastu k papírové ploše, ne kvůli dark mode.
class _OfficeRail extends StatelessWidget {
  const _OfficeRail({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.inbox_outlined, Icons.inbox, 'nav.inbox'.tr()),
      (Icons.people_outline, Icons.people, 'nav.clients'.tr()),
      (Icons.settings_outlined, Icons.settings, 'nav.settings'.tr()),
    ];
    return ColoredBox(
      color: AppTheme.nav,
      child: SizedBox(
        width: AppTheme.railWidth,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.navSelected,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: const Icon(
                  Icons.folder_open_rounded,
                  color: AppTheme.navInk,
                  size: 22,
                ),
              ),
              const SizedBox(height: 28),
              for (var i = 0; i < items.length; i++)
                _RailItem(
                  icon: selected == i ? items[i].$2 : items[i].$1,
                  label: items[i].$3,
                  selected: selected == i,
                  onTap: () => onSelect(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Material(
        color: selected ? AppTheme.navSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Icon(
                    icon,
                    color: selected ? AppTheme.navInk : AppTheme.navMuted,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? AppTheme.navInk : AppTheme.navMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
