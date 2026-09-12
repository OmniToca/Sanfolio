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
        return Scaffold(
          appBar: AppBar(title: Text('settings.title'.tr())),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('settings.intro'.tr()),
              const SizedBox(height: 8),
              Text('settings.cronHint'.tr()),
              const SizedBox(height: 16),
              Text('settings.staffLocaleHint'.tr()),
              const SizedBox(height: 8),
              DropdownMenu<String>(
                key: ValueKey(
                  ref.watch(authControllerProvider).valueOrNull?.profile?.locale ??
                      'cs',
                ),
                initialSelection:
                    ref.watch(authControllerProvider).valueOrNull?.profile?.locale ??
                        'cs',
                label: Text('settings.staffLocale'.tr()),
                expandedInsets: EdgeInsets.zero,
                dropdownMenuEntries: [
                  for (final code in appLocaleCodes)
                    DropdownMenuEntry(
                      value: code,
                      label: 'lang.$code'.tr(),
                    ),
                ],
                onSelected: (v) {
                  if (v == null) return;
                  ref.read(authControllerProvider.notifier).setStaffLocale(v);
                  context.setLocale(Locale(v));
                },
              ),
              const SizedBox(height: 16),
              AppCard(
                child: SwitchListTile(
                  title: Text(
                    s.displayName.isEmpty
                        ? 'settings.unnamedOffice'.tr()
                        : s.displayName,
                  ),
                  subtitle: Text('settings.sendTranslated'.tr()),
                  value: s.sendTranslatedOutbound,
                  onChanged: ctrl.setSendTranslatedOutbound,
                ),
              ),
              const SizedBox(height: 16),
              _DaysStepper(
                label: 'settings.plusvaliaDays'.tr(),
                value: s.plusvaliaDays,
                onChanged: ctrl.setPlusvaliaDays,
              ),
              _DaysStepper(
                label: 'settings.ibiDays'.tr(),
                value: s.ibiWarnDays,
                onChanged: ctrl.setIbiWarnDays,
              ),
              _DaysStepper(
                label: 'settings.ibiDueMonth'.tr(),
                value: s.ibiDueMonth,
                max: 12,
                onChanged: ctrl.setIbiDueMonth,
              ),
              _DaysStepper(
                label: 'settings.ibiDueDay'.tr(),
                value: s.ibiDueDay,
                max: 31,
                onChanged: ctrl.setIbiDueDay,
              ),
              _DaysStepper(
                label: 'settings.seguroDays'.tr(),
                value: s.seguroWarnDays,
                onChanged: ctrl.setSeguroWarnDays,
              ),
              _DaysStepper(
                label: 'settings.alarmaDays'.tr(),
                value: s.alarmaWarnDays,
                onChanged: ctrl.setAlarmaWarnDays,
              ),
              _DaysStepper(
                label: 'settings.poderDays'.tr(),
                value: s.poderWarnDays,
                onChanged: ctrl.setPoderWarnDays,
              ),
              _DaysStepper(
                label: 'settings.nudgeDays'.tr(),
                value: s.nudgeIntervalDays,
                onChanged: ctrl.setNudgeIntervalDays,
              ),
              _DaysStepper(
                label: 'settings.staleDays'.tr(),
                value: s.staleExpedienteDays,
                onChanged: ctrl.setStaleExpedienteDays,
              ),
              const SizedBox(height: 24),
              const OfficeTeamSection(),
              const SizedBox(height: 24),
              Text(
                'settings.blockOrder'.tr(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text('settings.blockOrderHint'.tr()),
              const SizedBox(height: 8),
              _BlockOrderList(
                settings: s,
                onMove: (keys) => ctrl.setCarpetaBlocksOrder(keys),
              ),
            ],
          ),
        );
      },
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
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(label),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: value > 0 ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            Text('$value'),
            IconButton(
              onPressed: max != null && value >= max!
                  ? null
                  : () => onChanged(value + 1),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockOrderList extends StatelessWidget {
  const _BlockOrderList({required this.settings, required this.onMove});

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
    return Column(
      children: [
        for (var i = 0; i < keys.length; i++)
          AppCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
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
          ),
      ],
    );
  }
}
