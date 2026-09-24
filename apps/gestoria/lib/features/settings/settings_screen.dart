import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/app_locales.dart';
import '../../core/modules/feature_gate.dart';
import '../../core/modules/slot_order.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../carpeta/bloque_template.dart';
import '../facturacion/facturacion_settings.dart';
import '../ofertas/ofertas_settings.dart';
import '../posta/posta_settings.dart';
import 'office_account_section.dart';
import 'office_modules_section.dart';
import 'office_settings_controller.dart';
import 'office_team_section.dart';
import 'settings_sections.dart';

/// Nastavení: list sekcí vlevo (široké) / nahoře (úzké). Žádná 6. ikona v railu.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.sectionKey});

  /// URL `/settings/:section` — např. `account`, `facturacion`.
  final String? sectionKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(officeSettingsProvider);
    final cfg = ref.watch(tenantConfigProvider).valueOrNull;
    final sections = visibleSettingsSections(cfg);
    final requested = parseSettingsSection(sectionKey);
    final selected = sections.contains(requested)
        ? requested!
        : (sections.isEmpty ? SettingsSectionId.office : sections.first);

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
        return Scaffold(
          appBar: appBar,
          body: _SettingsBody(
            sections: sections,
            selected: selected,
            settings: s,
            ctrl: ctrl,
            onSelect: (id) {
              if (id == selected) return;
              context.go('/settings/${id.routeKey}');
            },
          ),
        );
      },
    );
  }
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody({
    required this.sections,
    required this.selected,
    required this.settings,
    required this.ctrl,
    required this.onSelect,
  });

  final List<SettingsSectionId> sections;
  final SettingsSectionId selected;
  final OfficeSettings settings;
  final OfficeSettingsController ctrl;
  final ValueChanged<SettingsSectionId> onSelect;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final content = _sectionContent(selected);
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 220,
            child: Material(
              color: AppTheme.surface,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 16, 8, 24),
                children: [
                  for (final id in sections)
                    _NavTile(
                      label: id.labelKey.tr(),
                      selected: id == selected,
                      onTap: () => onSelect(id),
                    ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1, color: AppTheme.rule),
          Expanded(child: content),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            itemCount: sections.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final id = sections[i];
              final on = id == selected;
              return Material(
                color: on ? AppTheme.accentSoft : AppTheme.chipOff,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                child: InkWell(
                  onTap: () => onSelect(id),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusSm),
                      border: Border.all(
                        color: on ? AppTheme.accent : AppTheme.rule,
                      ),
                    ),
                    child: Text(
                      id.labelKey.tr(),
                      style:
                          Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: on ? AppTheme.accent : AppTheme.ink,
                                fontWeight:
                                    on ? FontWeight.w700 : FontWeight.w500,
                              ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1, color: AppTheme.rule),
        Expanded(child: content),
      ],
    );
  }

  Widget _sectionContent(SettingsSectionId id) {
    return switch (id) {
      SettingsSectionId.office => _OfficeTab(settings: settings, ctrl: ctrl),
      SettingsSectionId.account => const _AccountTab(),
      SettingsSectionId.team => const _TeamTab(),
      SettingsSectionId.deadlines =>
        _DeadlinesTab(settings: settings, ctrl: ctrl),
      SettingsSectionId.folder => _FolderTab(
          settings: settings,
          onMove: (keys) => ctrl.setCarpetaBlocksOrder(keys),
        ),
      SettingsSectionId.posta => _PostaTab(settings: settings),
      SettingsSectionId.facturacion =>
        _FacturacionTab(settings: settings),
      SettingsSectionId.ofertas => const _OfertasTab(),
    };
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? AppTheme.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: selected ? AppTheme.accent : AppTheme.ink,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
          ),
        ),
      ),
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

/// Tenant: licence + pravidla odchozích. Osobní účet a moduly jinde.
class _OfficeTab extends StatelessWidget {
  const _OfficeTab({required this.settings, required this.ctrl});

  final OfficeSettings settings;
  final OfficeSettingsController ctrl;

  @override
  Widget build(BuildContext context) {
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
              Text(
                'settings.officeIntro'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.pencil,
                    ),
              ),
              const SizedBox(height: 16),
              const OfficeModulesSection(),
              const SizedBox(height: 16),
              outbound,
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

/// Osobní: jazyk obrazovky, heslo, odhlášení. Ne tenant.
class _AccountTab extends ConsumerWidget {
  const _AccountTab();

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
    return ListView(
      children: [
        AppContent(
          maxWidth: AppTheme.contentWide,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'settings.accountIntro'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.pencil,
                    ),
              ),
              const SizedBox(height: 16),
              language,
              const SizedBox(height: 16),
              const OfficeAccountSection(),
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

class _PostaTab extends StatelessWidget {
  const _PostaTab({required this.settings});

  final OfficeSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        AppContent(
          maxWidth: AppTheme.contentWide,
          child: PostaIngestSection(settings: settings),
        ),
      ],
    );
  }
}

class _FacturacionTab extends StatelessWidget {
  const _FacturacionTab({required this.settings});

  final OfficeSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        AppContent(
          maxWidth: AppTheme.contentWide,
          child: FacturacionSettingsSection(settings: settings),
        ),
      ],
    );
  }
}

class _OfertasTab extends StatelessWidget {
  const _OfertasTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        AppContent(
          maxWidth: AppTheme.contentWide,
          child: OfertasSettingsSection(),
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
