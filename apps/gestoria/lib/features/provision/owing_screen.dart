import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/money/cents.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../carpeta/carpeta_routes.dart';
import 'owing.dart';
import 'owing_providers.dart';

/// Seznam dlužných záloh. Nachystat výzvu otevře compose — odesílá člověk.
class OwingScreen extends ConsumerWidget {
  const OwingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(owingListProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('provision.owingTitle'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/inbox'),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('provision.owingLoadError'.tr())),
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
                        title: 'provision.owingTitle'.tr(),
                        subtitle: 'provision.owingHint'.tr(),
                      ),
                      if (rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 48),
                          child: Text('provision.owingEmpty'.tr()),
                        )
                      else
                        for (final row in rows)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _OwingCard(row: row),
                          ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OwingCard extends StatelessWidget {
  const _OwingCard({required this.row});

  final OwingRow row;

  @override
  Widget build(BuildContext context) {
    final name = row.clienteNombre.isEmpty
        ? 'inbox.unnamed'.tr()
        : row.clienteNombre;
    return AppCard(
      stripe: row.remainingCents < 0
          ? AppTheme.statusAlert
          : AppTheme.statusWarn,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              [
                'provision.owingSaldo'.tr(
                  namedArgs: {'amount': formatCents(row.remainingCents)},
                ),
                'provision.owingReceived'.tr(
                  namedArgs: {'amount': formatCents(row.receivedCents)},
                ),
                'provision.owingInvoiced'.tr(
                  namedArgs: {'amount': formatCents(row.invoicedCents)},
                ),
              ].join(' · '),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.pencil),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FeatureGate(
                  module: GestoriaModule.messaging,
                  child: FilledButton(
                    onPressed: () {
                      final q = Uri(
                        path: '/clientes/${row.clienteId}/mensaje',
                        queryParameters: {
                          'tpl': 'recordatorio',
                          'bloque': 'provision_factura',
                        },
                      );
                      context.go('${q.path}?${q.query}');
                    },
                    child: Text('provision.owingDraft'.tr()),
                  ),
                ),
                TextButton(
                  onPressed: () => context.go(
                    carpetaBloqueRoute(
                      row.clienteId,
                      'provision_factura',
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
