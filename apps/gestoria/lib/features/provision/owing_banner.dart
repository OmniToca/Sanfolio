import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import 'owing_providers.dart';

/// Slot `inbox.feed`: záloha remaining <= 0. Ne ikona v railu.
class OwingInboxBanner extends ConsumerWidget {
  const OwingInboxBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(owingCountProvider).valueOrNull ?? 0;
    if (n <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        stripe: AppTheme.statusAlert,
        onTap: () => context.go('/dluh'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'provision.owingBadge'.tr(namedArgs: {'count': '$n'}),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text('provision.owingOpen'.tr()),
            ],
          ),
        ),
      ),
    );
  }
}
