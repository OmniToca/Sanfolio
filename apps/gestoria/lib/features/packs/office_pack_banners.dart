import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import 'office_packs_providers.dart';

/// Inbox: jeden vstup pro 210 i koupě po notáři. Ne dvě karty, ne ikona v railu.
class OfficePacksInboxBanner extends ConsumerWidget {
  const OfficePacksInboxBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(tenantConfigProvider).valueOrNull;
    final seasonOn = cfg?.isOn(GestoriaModule.impuestos) ?? false;
    final notaryOn = cfg?.isOn(GestoriaModule.carpetaInmueble) ?? false;
    final season =
        seasonOn ? (ref.watch(season210CountProvider).valueOrNull ?? 0) : 0;
    final notary =
        notaryOn ? (ref.watch(afterNotaryCountProvider).valueOrNull ?? 0) : 0;
    final n = season + notary;
    if (n <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        stripe: AppTheme.statusWarn,
        onTap: () => context.go('/kampane'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              const Icon(Icons.assignment_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'packs.campaignBadge'.tr(namedArgs: {'count': '$n'}),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text('packs.campaignOpen'.tr()),
            ],
          ),
        ),
      ),
    );
  }
}
