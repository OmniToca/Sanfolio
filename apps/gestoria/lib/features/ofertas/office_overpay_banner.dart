import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import 'office_overpay_providers.dart';

/// Slot `inbox.feed`: kdo z faktur platí víc než tarif kanceláře.
class OverpayInboxBanner extends ConsumerWidget {
  const OverpayInboxBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(overpayCountProvider).valueOrNull ?? 0;
    if (n <= 0) return const SizedBox.shrink();
    return FeatureGate(
      module: GestoriaModule.ofertas,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: AppCard(
          stripe: AppTheme.statusWarn,
          onTap: () => context.go('/preplatek'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                const Icon(Icons.savings_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'ofertas.overpayBadge'.tr(namedArgs: {'count': '$n'}),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text('ofertas.overpayOpen'.tr()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
