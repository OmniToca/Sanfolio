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
import 'office_offers.dart';
import 'office_overpay_providers.dart';

/// Seznam přeplatků. Nachystat výzvu otevře compose — odesílá člověk.
class OverpayScreen extends ConsumerWidget {
  const OverpayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(overpayListProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('ofertas.overpayTitle'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/inbox'),
        ),
      ),
      body: FeatureGate(
        module: GestoriaModule.ofertas,
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('ofertas.overpayLoadError'.tr())),
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
                          title: 'ofertas.overpayTitle'.tr(),
                          subtitle: 'ofertas.overpayHint'.tr(),
                        ),
                        if (rows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 48),
                            child: Text('ofertas.overpayEmpty'.tr()),
                          )
                        else
                          for (final row in rows)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _OverpayCard(row: row),
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

class _OverpayCard extends StatelessWidget {
  const _OverpayCard({required this.row});

  final OverpayRow row;

  @override
  Widget build(BuildContext context) {
    final name = row.clienteNombre.isEmpty
        ? 'inbox.unnamed'.tr()
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
              'ofertas.compare'.tr(
                namedArgs: {
                  'current': formatCents(row.clientAnnualCents),
                  'name': row.offerTitle,
                  'offer': formatCents(row.offerAnnualCents),
                },
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.pencil,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              [
                'blocks.${row.bloqueKey}'.tr(),
                'ofertas.overpaySaving'.tr(
                  namedArgs: {'amount': formatCents(row.savingCents)},
                ),
              ].join(' · '),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () {
                    final q = Uri(
                      path: '/clientes/${row.clienteId}/mensaje',
                      queryParameters: {
                        'tpl': 'oferta_suministro',
                        'bloque': row.bloqueKey,
                        'documento': row.offerTitle,
                      },
                    );
                    context.go('${q.path}?${q.query}');
                  },
                  child: Text('ofertas.draft'.tr()),
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
