import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../carpeta/carpeta_routes.dart';
import '../posta/posta_providers.dart';
import 'extract_queue.dart';
import 'extract_queue_providers.dart';

/// Třídírna přepisů. Stejné Guardar / Zahodit jako na desce. AI neukládá.
class ExtractQueueScreen extends ConsumerWidget {
  const ExtractQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(extractQueueProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('prepis.title'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/inbox'),
        ),
      ),
      body: FeatureGate(
        module: GestoriaModule.aiCopilot,
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('prepis.loadError'.tr())),
          data: (rows) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppTheme.contentWide,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppPageHeader(
                          title: 'prepis.title'.tr(),
                          subtitle: 'prepis.subtitle'.tr(),
                        ),
                        if (rows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 48),
                            child: Text('prepis.empty'.tr()),
                          )
                        else
                          for (final row in rows)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _ExtractQueueCard(row: row),
                            ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ExtractQueueCard extends ConsumerWidget {
  const _ExtractQueueCard({required this.row});

  final ExtractQueueRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proposed = extractProposalFields(row.fields);
    final paper = (row.docTipo ?? '').trim();
    final name = row.clienteNombre.isEmpty
        ? 'prepis.unnamed'.tr()
        : row.clienteNombre;
    return AppCard(
      stripe: AppTheme.statusWarn,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              [
                'blocks.${row.bloqueKey}'.tr(),
                if (paper.isNotEmpty) 'docs.$paper'.tr(),
                if ((row.originalName ?? '').isNotEmpty) row.originalName!,
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.pencil,
                  ),
            ),
            if (row.pending) ...[
              const SizedBox(height: 12),
              Text('prepis.pending'.tr()),
            ],
            if (row.failed) ...[
              const SizedBox(height: 12),
              Text('prepis.failed'.tr()),
            ],
            if (proposed.isNotEmpty) ...[
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.proposal,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ai.proposalBadge'.tr()),
                      const SizedBox(height: 6),
                      for (final e in proposed.entries.take(12))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '${e.key.tr()}: ${e.value}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: !row.canGuardar
                      ? null
                      : () async {
                          final ok = await applyExtractQueueRow(
                            ref: ref,
                            row: row,
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok ? 'prepis.saved'.tr() : 'prepis.saveError'.tr(),
                              ),
                            ),
                          );
                        },
                  child: Text('ai.apply'.tr()),
                ),
                TextButton(
                  onPressed: () async {
                    await discardExtractQueueRow(ref: ref, row: row);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('prepis.discarded'.tr())),
                    );
                  },
                  child: Text('ai.discard'.tr()),
                ),
                if ((row.storagePath ?? '').isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      try {
                        final url = await signedPostaUrl(row.storagePath!);
                        await launchUrl(Uri.parse(url));
                      } on Object {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('folder.openError'.tr())),
                        );
                      }
                    },
                    child: Text('prepis.original'.tr()),
                  ),
                TextButton(
                  onPressed: () => context.go(
                    carpetaBloqueRoute(
                      row.clienteId,
                      row.bloqueKey,
                      expedienteId: row.expedienteId,
                    ),
                  ),
                  child: Text('folder.openBlock'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
