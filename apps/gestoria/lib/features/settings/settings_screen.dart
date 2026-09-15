import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/i18n/app_locales.dart';
import '../../core/modules/slot_order.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../carpeta/bloque_template.dart';
import '../facturacion/facturacion_settings.dart';
import '../posta/posta_settings.dart';
import 'office_account_section.dart';
import 'office_settings_controller.dart';
import 'office_team_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(officeSettingsProvider);
    final appBar = AppBar(
      title: Text('settings.title'.tr()),
      actions: _signOutActions(context, ref),
    );
    return async.when(
      loading: () => Scaffold(
        appBar: appBar,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: appBar,
        body: ListView(
          children: [
            AppContent(
              maxWidth: AppTheme.contentWide,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    e is MissingOfficeTenant
                        ? 'settings.noTenant'.tr()
                        : 'settings.loadError'.tr(),
                  ),
                  const SizedBox(height: 16),
                  const OfficeAccountSection(),
                ],
              ),
            ),
          ],
        ),
      ),
      data: (s) {
        final ctrl = ref.read(officeSettingsProvider.notifier);
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: Text('settings.title'.tr()),
              actions: _signOutActions(context, ref),
              bottom: TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'settings.tabOffice'.tr()),
                  Tab(text: 'settings.tabDeadlines'.tr()),
                  Tab(text: 'settings.tabTeam'.tr()),
                  Tab(text: 'settings.tabFolder'.tr()),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _OfficeTab(settings: s, ctrl: ctrl),
                _DeadlinesTab(settings: s, ctrl: ctrl),
                const _TeamTab(),
                _FolderTab(
                  settings: s,
                  onMove: (keys) => ctrl.setCarpetaBlocksOrder(keys),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

List<Widget> _signOutActions(BuildContext context, WidgetRef ref) {
  if (MediaQuery.sizeOf(context).width >= 720) return const [];
  final impersonating =
      ref.watch(authControllerProvider).valueOrNull?.impersonating == true;
  return [
    TextButton(
      onPressed: () {
        final auth = ref.read(authControllerProvider.notifier);
        if (impersonating) {
          auth.endImpersonationAndReturnToSupport();
        } else {
          auth.signOut();
        }
      },
      child: Text(
        impersonating ? 'impersonation.end'.tr() : 'auth.signOut'.tr(),
      ),
    ),
  ];
}

class _OfficeTab extends ConsumerWidget {
  const _OfficeTab({required this.settings, required this.ctrl});

  final OfficeSettings settings;
  final OfficeSettingsController ctrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale =
        ref.watch(authControllerProvider).valueOrNull?.profile?.locale ?? 'cs';
    final language = AppSectionCard(
      title: 'settings.staffLocale'.tr(),
      hint: 'settings.staffLocaleHint'.tr(),
      child: DropdownButtonFormField<String>(
        key: ValueKey(locale),
        value: locale,
        decoration: InputDecoration(labelText: 'settings.staffLocale'.tr()),
        items: [
          for (final code in appLocaleCodes)
            DropdownMenuItem(
              value: code,
              child: Text('lang.$code'.tr()),
            ),
        ],
        onChanged: (v) {
          if (v == null) return;
          ref.read(authControllerProvider.notifier).setStaffLocale(v);
          context.setLocale(Locale(v));
        },
      ),
    );
    final outbound = AppSectionCard(
      title: 'settings.outboundTitle'.tr(),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          settings.displayName.isEmpty
              ? 'settings.unnamedOffice'.tr()
              : settings.displayName,
        ),
        subtitle: Text('settings.sendTranslated'.tr()),
        value: settings.sendTranslatedOutbound,
        onChanged: ctrl.setSendTranslatedOutbound,
      ),
    );
    return ListView(
      children: [
        AppContent(
          maxWidth: AppTheme.contentWide,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 900) {
                    return Column(
                      children: [
                        language,
                        const SizedBox(height: 16),
                        outbound,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: language),
                      const SizedBox(width: 16),
                      Expanded(child: outbound),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              const PostaIngestSection(),
              const SizedBox(height: 16),
              const OfficeAccountSection(),
              const SizedBox(height: 16),
              FacturacionSettingsSection(settings: settings),
              const SizedBox(height: 16),
              Text(
                'settings.cronHint'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.pencil,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeadlinesTab extends StatelessWidget {
  const _DeadlinesTab({required this.settings, required this.ctrl});

  final OfficeSettings settings;
  final OfficeSettingsController ctrl;

  @override
  Widget build(BuildContext context) {
    final tax = AppSectionCard(
      title: 'settings.groupTax'.tr(),
      child: Column(
        children: [
          _DaysStepper(
            label: 'settings.plusvaliaDays'.tr(),
            value: settings.plusvaliaDays,
            onChanged: ctrl.setPlusvaliaDays,
          ),
          _DaysStepper(
            label: 'settings.ibiDays'.tr(),
            value: settings.ibiWarnDays,
            onChanged: ctrl.setIbiWarnDays,
          ),
          _DaysStepper(
            label: 'settings.ibiDueMonth'.tr(),
            value: settings.ibiDueMonth,
            onChanged: ctrl.setIbiDueMonth,
            max: 12,
          ),
          _DaysStepper(
            label: 'settings.ibiDueDay'.tr(),
            value: settings.ibiDueDay,
            onChanged: ctrl.setIbiDueDay,
            max: 31,
          ),
        ],
      ),
    );
    final cover = AppSectionCard(
      title: 'settings.groupCover'.tr(),
      child: Column(
        children: [
          _DaysStepper(
            label: 'settings.seguroDays'.tr(),
            value: settings.seguroWarnDays,
            onChanged: ctrl.setSeguroWarnDays,
          ),
          _DaysStepper(
            label: 'settings.alarmaDays'.tr(),
            value: settings.alarmaWarnDays,
            onChanged: ctrl.setAlarmaWarnDays,
          ),
          _DaysStepper(
            label: 'settings.poderDays'.tr(),
            value: settings.poderWarnDays,
            onChanged: ctrl.setPoderWarnDays,
          ),
        ],
      ),
    );
    final follow = AppSectionCard(
      title: 'settings.groupFollowup'.tr(),
      child: Column(
        children: [
          _DaysStepper(
            label: 'settings.nudgeDays'.tr(),
            value: settings.nudgeIntervalDays,
            onChanged: ctrl.setNudgeIntervalDays,
          ),
          _DaysStepper(
            label: 'settings.staleDays'.tr(),
            value: settings.staleExpedienteDays,
            onChanged: ctrl.setStaleExpedienteDays,
          ),
        ],
      ),
    );
    return ListView(
      children: [
        AppContent(
          maxWidth: AppTheme.contentWide,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'settings.intro'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.pencil,
                    ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 900) {
                    return Column(
                      children: [
                        tax,
                        const SizedBox(height: 16),
                        cover,
                        const SizedBox(height: 16),
                        follow,
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: tax),
                          const SizedBox(width: 16),
                          Expanded(child: cover),
                        ],
                      ),
                      const SizedBox(height: 16),
                      follow,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DaysStepper extends StatelessWidget {
  const _DaysStepper({
    required this.label,
    required this.value,
    required this.onChanged,
    this.max,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int? max;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: AppTheme.surfaceMuted,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: value > 0 ? () => onChanged(value - 1) : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '$value',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: max != null && value >= max!
                      ? null
                      : () => onChanged(value + 1),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamTab extends StatelessWidget {
  const _TeamTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        AppContent(
          maxWidth: AppTheme.contentWide,
          child: OfficeTeamSection(),
        ),
      ],
    );
  }
}

class _FolderTab extends StatelessWidget {
  const _FolderTab({required this.settings, required this.onMove});

  final OfficeSettings settings;
  final ValueChanged<List<String>> onMove;

  @override
  Widget build(BuildContext context) {
    final catalog = [for (final t in compraventaBloques) t.key];
    final keys = applySlotOrder(
      items: catalog,
      order: slotKeys(settings.slotOrder, carpetaBlocksSlot),
      keyOf: (k) => k,
    );
    Widget row(int i) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppInsetRow(
          leading: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppTheme.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${i + 1}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          title: 'blocks.${keys[i]}'.tr(),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'settings.moveUp'.tr(),
                visualDensity: VisualDensity.compact,
                onPressed:
                    i == 0 ? null : () => onMove(moveKey(keys, i, -1)),
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              IconButton(
                tooltip: 'settings.moveDown'.tr(),
                visualDensity: VisualDensity.compact,
                onPressed: i == keys.length - 1
                    ? null
                    : () => onMove(moveKey(keys, i, 1)),
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      children: [
        AppContent(
          maxWidth: AppTheme.contentWide,
          child: AppSectionCard(
            title: 'settings.blockOrder'.tr(),
            hint: 'settings.blockOrderHint'.tr(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 900) {
                  return Column(
                    children: [for (var i = 0; i < keys.length; i++) row(i)],
                  );
                }
                final mid = (keys.length / 2).ceil();
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          for (var i = 0; i < mid; i++) row(i),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          for (var i = mid; i < keys.length; i++) row(i),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
