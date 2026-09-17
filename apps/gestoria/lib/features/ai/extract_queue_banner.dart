import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import 'extract_queue_providers.dart';

/// Slot `inbox.feed`: přepisy čekající na Guardar. Ne nová ikona v railu.
class ExtractQueueBanner extends ConsumerWidget {
  const ExtractQueueBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(extractQueueCountProvider).valueOrNull ?? 0;
    if (n <= 0) return const SizedBox.shrink();
    return FeatureGate(
      module: GestoriaModule.aiCopilot,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: AppCard(
          stripe: AppTheme.statusWarn,
          onTap: () => context.go('/prepis'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                const Icon(Icons.edit_note_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'prepis.badge'.tr(namedArgs: {'count': '$n'}),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text('prepis.open'.tr()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
