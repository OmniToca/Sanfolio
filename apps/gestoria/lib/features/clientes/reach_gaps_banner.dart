import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import 'reach_gaps_providers.dart';

/// Slot `inbox.feed`: karty bez kanálu nebo locale. Ne ikona v railu.
class ReachGapsInboxBanner extends ConsumerWidget {
  const ReachGapsInboxBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(reachGapsCountProvider).valueOrNull ?? 0;
    if (n <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        stripe: AppTheme.statusWarn,
        onTap: () => context.go('/kanal'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              const Icon(Icons.phonelink_erase_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'clients.reachBadge'.tr(namedArgs: {'count': '$n'}),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text('clients.reachOpen'.tr()),
            ],
          ),
        ),
      ),
    );
  }
}
