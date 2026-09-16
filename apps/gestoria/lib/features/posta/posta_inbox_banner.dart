import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import 'posta_providers.dart';

/// Slot `inbox.feed`: nepřiřazené přílohy a přiřazené čekající na desku.
class PostaInboxBanner extends ConsumerWidget {
  const PostaInboxBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unassigned =
        ref.watch(postaUnassignedCountProvider).valueOrNull ?? 0;
    final unfiled = ref.watch(postaUnfiledCountProvider).valueOrNull ?? 0;
    if (unassigned <= 0 && unfiled <= 0) return const SizedBox.shrink();
    return FeatureGate(
      module: GestoriaModule.messaging,
      child: Column(
        children: [
          if (unassigned > 0)
            _PostaCountCard(
              text: 'posta.badge'.tr(namedArgs: {'count': '$unassigned'}),
              onTap: () {
                ref.read(postaFilterProvider.notifier).state = 'unassigned';
                context.go('/posta');
              },
            ),
          if (unfiled > 0)
            _PostaCountCard(
              text: 'posta.badgeUnfiled'.tr(namedArgs: {'count': '$unfiled'}),
              onTap: () {
                ref.read(postaFilterProvider.notifier).state = 'unfiled';
                context.go('/posta');
              },
            ),
        ],
      ),
    );
  }
}

class _PostaCountCard extends StatelessWidget {
  const _PostaCountCard({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        stripe: AppTheme.statusWarn,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              const Icon(Icons.mail_outline),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text('posta.openInbox'.tr()),
            ],
          ),
        ),
      ),
    );
  }
}
