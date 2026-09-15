import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
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
            return Row(
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
            );
          },
        ),
      ),
    );
  }
}
