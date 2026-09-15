import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/theme/app_theme.dart';
import '../../core/presentation/widgets/sanfolio_brand.dart';
import '../ai/ai_chat.dart';
import '../ai/ai_panel.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 720;
    final impersonation = ref
        .watch(authControllerProvider)
        .valueOrNull
        ?.impersonation;
    final cfg = ref.watch(tenantConfigProvider).valueOrNull;
    final aiOn = cfg?.isOn(GestoriaModule.aiCopilot) ?? false;
    final facturacionOn = cfg?.isOn(GestoriaModule.facturacion) ?? false;
    final postaOn = cfg?.isOn(GestoriaModule.messaging) ?? false;
    final paths = [
      '/inbox',
      if (postaOn) '/posta',
      '/clientes',
      if (facturacionOn) '/facturacion',
      '/settings',
    ];
    int indexFor(String loc) {
      if (loc.startsWith('/settings')) return paths.indexOf('/settings');
      if (loc.startsWith('/facturacion')) {
        final i = paths.indexOf('/facturacion');
        return i < 0 ? 0 : i;
      }
      if (loc.startsWith('/clientes')) return paths.indexOf('/clientes');
      if (loc.startsWith('/posta')) {
        final i = paths.indexOf('/posta');
        return i < 0 ? 0 : i;
      }
      return 0;
    }

    final selected = indexFor(location);
    final panelOpen =
        aiOn &&
        aiPanelVisible(
          width: size.width,
          preference: ref.watch(aiPanelOpenProvider),
        );
    final docked = panelOpen && aiPanelDocked(size.width);

    void goIndex(int i) => context.go(paths[i]);

    void toggleAi() {
      ref.read(aiPanelOpenProvider.notifier).state = !panelOpen;
    }

    final destinations = [
      NavigationDestination(
        icon: const Icon(Icons.inbox_outlined),
        selectedIcon: const Icon(Icons.inbox),
        label: 'nav.inbox'.tr(),
      ),
      if (postaOn)
        NavigationDestination(
          icon: const Icon(Icons.mail_outline),
          selectedIcon: const Icon(Icons.mail),
          label: 'nav.posta'.tr(),
        ),
      NavigationDestination(
        icon: const Icon(Icons.folder_outlined),
        selectedIcon: const Icon(Icons.folder),
        label: 'nav.clients'.tr(),
      ),
      if (facturacionOn)
        NavigationDestination(
          icon: const Icon(Icons.receipt_long_outlined),
          selectedIcon: const Icon(Icons.receipt_long),
          label: 'nav.invoices'.tr(),
        ),
      NavigationDestination(
        icon: const Icon(Icons.tune_outlined),
        selectedIcon: const Icon(Icons.tune),
        label: 'nav.settings'.tr(),
      ),
      if (aiOn)
        NavigationDestination(
          icon: const Icon(Icons.auto_awesome_outlined),
          selectedIcon: const Icon(Icons.auto_awesome),
          label: 'ai.title'.tr(),
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

    Widget wrapPanel({required double width}) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: AppTheme.rule)),
        ),
        child: SizedBox(
          width: width,
          child: AiPanel(onClose: toggleAi),
        ),
      );
    }

    Widget withOverlay(Widget body, {required bool show}) {
      if (!show) return body;
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth < AppTheme.aiPanelWidth
              ? constraints.maxWidth
              : AppTheme.aiPanelWidth;
          return Stack(
            children: [
              body,
              Positioned.fill(
                child: GestureDetector(
                  onTap: toggleAi,
                  child: const ColoredBox(color: AppTheme.scrim),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: width,
                child: wrapPanel(width: width),
              ),
            ],
          );
        },
      );
    }

    if (!wide) {
      return Scaffold(
        body: withBanner(withOverlay(child, show: panelOpen)),
        bottomNavigationBar: NavigationBar(
          selectedIndex: panelOpen ? destinations.length - 1 : selected,
          onDestinationSelected: (i) {
            if (aiOn && i == destinations.length - 1) {
              toggleAi();
              return;
            }
            goIndex(i);
          },
          destinations: destinations,
        ),
      );
    }

    return Scaffold(
      body: withBanner(
        Row(
          children: [
            _OfficeRail(
              selected: selected,
              aiSelected: panelOpen,
              showAi: aiOn,
              showPosta: postaOn,
              showFacturacion: facturacionOn,
              onSelect: goIndex,
              onAi: toggleAi,
              signOutLabel: impersonation == null
                  ? 'auth.signOut'.tr()
                  : 'impersonation.end'.tr(),
              onSignOut: () {
                final auth = ref.read(authControllerProvider.notifier);
                if (impersonation != null) {
                  auth.endImpersonationAndReturnToSupport();
                } else {
                  auth.signOut();
                }
              },
            ),
            Expanded(child: withOverlay(child, show: panelOpen && !docked)),
            if (docked) wrapPanel(width: AppTheme.aiPanelWidth),
          ],
        ),
      ),
    );
  }
}

/// Levý pruh. Tmavý kvůli kontrastu k papírové ploše, ne kvůli dark mode.
class _OfficeRail extends StatelessWidget {
  const _OfficeRail({
    required this.selected,
    required this.aiSelected,
    required this.showAi,
    required this.showPosta,
    required this.showFacturacion,
    required this.onSelect,
    required this.onAi,
    required this.signOutLabel,
    required this.onSignOut,
  });

  final int selected;
  final bool aiSelected;
  final bool showAi;
  final bool showPosta;
  final bool showFacturacion;
  final ValueChanged<int> onSelect;
  final VoidCallback onAi;
  final String signOutLabel;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.inbox_outlined, Icons.inbox, 'nav.inbox'.tr()),
      if (showPosta) (Icons.mail_outline, Icons.mail, 'nav.posta'.tr()),
      (Icons.folder_outlined, Icons.folder, 'nav.clients'.tr()),
      if (showFacturacion)
        (
          Icons.receipt_long_outlined,
          Icons.receipt_long,
          'nav.invoices'.tr(),
        ),
      (Icons.tune_outlined, Icons.tune, 'nav.settings'.tr()),
    ];
    return ColoredBox(
      color: AppTheme.nav,
      child: SizedBox(
        width: AppTheme.railWidth,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 22),
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.navInk,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: const SanfolioMark(size: 26),
              ),
              const SizedBox(height: 28),
              for (var i = 0; i < items.length; i++)
                _RailItem(
                  icon: selected == i ? items[i].$2 : items[i].$1,
                  label: items[i].$3,
                  selected: selected == i,
                  onTap: () => onSelect(i),
                ),
              const Spacer(),
              if (showAi)
                FeatureGate(
                  module: GestoriaModule.aiCopilot,
                  child: _RailItem(
                    icon: Icons.auto_awesome,
                    label: 'ai.title'.tr(),
                    selected: aiSelected,
                    onTap: onAi,
                  ),
                ),
              _RailItem(
                icon: Icons.logout,
                label: signOutLabel,
                selected: false,
                onTap: onSignOut,
              ),
              const SizedBox(height: 16),
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
                    size: 22,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.2,
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
