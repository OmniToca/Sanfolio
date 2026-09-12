import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/i18n/app_locales.dart';
import '../../core/modules/slot_order.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../carpeta/bloque_template.dart';
import 'office_settings_controller.dart';
import 'office_team_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(officeSettingsProvider);
    return async.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text('settings.title'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: Text('settings.title'.tr())),
        body: Center(
          child: Text(
            e is MissingOfficeTenant
                ? 'settings.noTenant'.tr()
                : 'settings.loadError'.tr(),
          ),
        ),
      ),
      data: (s) {
        final ctrl = ref.read(officeSettingsProvider.notifier);
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: Text('settings.title'.tr()),
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
                ListView(
                  children: const [
                    AppContent(child: OfficeTeamSection(showHeading: false)),
                  ],
                ),
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

class _OfficeTab extends ConsumerWidget {
  const _OfficeTab({required this.settings, required this.ctrl});

  final OfficeSettings settings;
  final OfficeSettingsController ctrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale =
        ref.watch(authControllerProvider).valueOrNull?.profile?.locale ?? 'cs';
    return ListView(
      children: [
        AppContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('settings.intro'.tr()),
              const SizedBox(height: 6),
              Text(
                'settings.cronHint'.tr(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Text(
                'settings.staffLocaleHint'.tr(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey(locale),
                value: locale,
                decoration:
                    InputDecoration(labelText: 'settings.staffLocale'.tr()),
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
              const SizedBox(height: 16),
              AppCard(
                child: SwitchListTile(
                  title: Text(
                    settings.displayName.isEmpty
                        ? 'settings.unnamedOffice'.tr()
                        : settings.displayName,
                  ),
                  subtitle: Text('settings.sendTranslated'.tr()),
                  value: settings.sendTranslatedOutbound,
                  onChanged: ctrl.setSendTranslatedOutbound,
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
    final rows = <(String, int, ValueChanged<int>, int?)>[
      (
        'settings.plusvaliaDays',
        settings.plusvaliaDays,
        ctrl.setPlusvaliaDays,
        null,
      ),
      ('settings.ibiDays', settings.ibiWarnDays, ctrl.setIbiWarnDays, null),
      (
        'settings.ibiDueMonth',
        settings.ibiDueMonth,
        ctrl.setIbiDueMonth,
        12,
      ),
      ('settings.ibiDueDay', settings.ibiDueDay, ctrl.setIbiDueDay, 31),
      (
        'settings.seguroDays',
        settings.seguroWarnDays,
        ctrl.setSeguroWarnDays,
        null,
      ),
      (
        'settings.alarmaDays',
        settings.alarmaWarnDays,
        ctrl.setAlarmaWarnDays,
        null,
      ),
      (
        'settings.poderDays',
        settings.poderWarnDays,
        ctrl.setPoderWarnDays,
        null,
      ),
      (
        'settings.nudgeDays',
        settings.nudgeIntervalDays,
        ctrl.setNudgeIntervalDays,
        null,
      ),
      (
        'settings.staleDays',
        settings.staleExpedienteDays,
        ctrl.setStaleExpedienteDays,
        null,
      ),
    ];
    return ListView(
      children: [
        AppContent(
          child: AppCard(
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _DaysStepper(
                    label: rows[i].$1.tr(),
                    value: rows[i].$2,
                    onChanged: rows[i].$3,
                    max: rows[i].$4,
                  ),
                ],
              ],
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            onPressed: max != null && value >= max!
                ? null
                : () => onChanged(value + 1),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
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
    return ListView(
      children: [
        AppContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'settings.blockOrder'.tr(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'settings.blockOrderHint'.tr(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(
                  children: [
                    for (var i = 0; i < keys.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 12,
                          child: Text(
                            '${i + 1}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        title: Text('blocks.${keys[i]}'.tr()),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'settings.moveUp'.tr(),
                              onPressed: i == 0
                                  ? null
                                  : () => onMove(moveKey(keys, i, -1)),
                              icon: const Icon(Icons.keyboard_arrow_up),
                            ),
                            IconButton(
                              tooltip: 'settings.moveDown'.tr(),
                              onPressed: i == keys.length - 1
                                  ? null
                                  : () => onMove(moveKey(keys, i, 1)),
                              icon: const Icon(Icons.keyboard_arrow_down),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
