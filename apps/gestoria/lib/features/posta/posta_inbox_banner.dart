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
    final bounce = ref.watch(postaBounceCountProvider).valueOrNull ?? 0;
    if (unassigned <= 0 && unfiled <= 0 && bounce <= 0) {
      return const SizedBox.shrink();
    }
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
          if (bounce > 0)
            _PostaCountCard(
              text: 'posta.badgeBounce'.tr(namedArgs: {'count': '$bounce'}),
              stripe: AppTheme.statusAlert,
              onTap: () => context.go('/posta'),
            ),
        ],
      ),
    );
  }
}

class _PostaCountCard extends StatelessWidget {
  const _PostaCountCard({
    required this.text,
    required this.onTap,
    this.stripe = AppTheme.statusWarn,
  });

  final String text;
  final VoidCallback onTap;
  final Color stripe;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        stripe: stripe,
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
