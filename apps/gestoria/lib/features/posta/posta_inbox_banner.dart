import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import 'posta_providers.dart';

/// Slot `inbox.feed`: jen počet nepřiřazených mailů s přílohou, ne druhá schránka.
class PostaInboxBanner extends ConsumerWidget {
  const PostaInboxBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(postaUnassignedCountProvider).valueOrNull ?? 0;
    if (count <= 0) return const SizedBox.shrink();
    return FeatureGate(
      module: GestoriaModule.messaging,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: AppCard(
          stripe: AppTheme.statusWarn,
          onTap: () => context.go('/posta'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                const Icon(Icons.mail_outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'posta.badge'.tr(namedArgs: {'count': '$count'}),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text('posta.openInbox'.tr()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
