import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import 'office_citas_providers.dart';

/// Slot `inbox.feed`: city dnes. Ne ikona v railu.
class CitasInboxBanner extends ConsumerWidget {
  const CitasInboxBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(citasTodayCountProvider).valueOrNull ?? 0;
    if (n <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        stripe: AppTheme.statusWarn,
        onTap: () => context.go('/citas'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              const Icon(Icons.event_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'citas.badge'.tr(namedArgs: {'count': '$n'}),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text('citas.open'.tr()),
            ],
          ),
        ),
      ),
    );
  }
}
