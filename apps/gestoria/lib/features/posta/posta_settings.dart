import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import 'posta_providers.dart';

/// Slot `settings.section`: kam Gmail posílá kopii kancelářské schránky.
class PostaIngestSection extends ConsumerWidget {
  const PostaIngestSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(postaAccountProvider);
    return FeatureGate(
      module: GestoriaModule.messaging,
      child: AppSectionCard(
        title: 'posta.ingestTitle'.tr(),
        hint: 'posta.ingestHint'.tr(),
        child: async.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, st) => Text('posta.loadError'.tr()),
          data: (account) {
            final addr = account?.ingestAddress ?? '';
            if (addr.isEmpty) {
              return Text('posta.loadError'.tr());
            }
            final steps = [
              'posta.ingestStep1'.tr(),
              'posta.ingestStep2'.tr(),
              'posta.ingestStep3'.tr(),
              'posta.ingestStep4'.tr(),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        addr,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'posta.ingestCopy'.tr(),
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: addr));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('posta.ingestCopied'.tr())),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${i + 1}. ${steps[i]}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.pencil,
                          ),
                    ),
                  ),
                Text(
                  'posta.ingestManyOffices'.tr(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
