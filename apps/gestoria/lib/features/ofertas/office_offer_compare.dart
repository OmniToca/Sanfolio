import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/money/cents.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../ai/paper_glance.dart';
import 'office_offers.dart';
import 'office_offers_providers.dart';

/// Slot `carpeta.blocks`: kolik platí vs. nabídka kanceláře. AI neodesílá.
class OfficeOfferCompareCard extends ConsumerWidget {
  const OfficeOfferCompareCard({
    super.key,
    required this.clienteId,
    required this.bloqueKey,
    required this.glance,
  });

  final String clienteId;
  final String bloqueKey;
  final PaperStackGlance glance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!offerKindForBloque(bloqueKey)) return const SizedBox.shrink();
    final offers = ref.watch(officeOffersProvider).valueOrNull ?? const [];
    final lines = compareOfficeOffers(
      bloqueKey: bloqueKey,
      glance: glance,
      offers: offers,
    );
    return FeatureGate(
      module: GestoriaModule.ofertas,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: AppCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ofertas.compareTitle'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (lines.isEmpty)
                  Text(
                    'ofertas.noOffers'.tr(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.pencil,
                        ),
                  )
                else ...[
                  for (final line in lines.take(5))
                    _CompareLine(
                      clienteId: clienteId,
                      bloqueKey: bloqueKey,
                      line: line,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompareLine extends StatelessWidget {
  const _CompareLine({
    required this.clienteId,
    required this.bloqueKey,
    required this.line,
  });

  final String clienteId;
  final String bloqueKey;
  final OfferCompareLine line;

  @override
  Widget build(BuildContext context) {
    final measure = supplyMeasureKey(bloqueKey).tr();
    final current = line.clientAnnualCents;
    final offer = line.offerAnnualCents;
    final text = current != null && offer != null
        ? 'ofertas.compare'.tr(
            namedArgs: {
              'current': formatCents(current),
              'name': line.offer.title,
              'offer': formatCents(offer),
            },
          )
        : line.clientUnitCents != null && line.offerUnitCents != null
            ? 'ofertas.compareUnit'.tr(
                namedArgs: {
                  'current': formatCents(line.clientUnitCents!),
                  'measure': measure,
                  'name': line.offer.title,
                  'offer': formatCents(line.offerUnitCents!),
                },
              )
            : current == null
                ? 'ofertas.noPrice'.tr()
                : 'ofertas.compare'.tr(
                    namedArgs: {
                      'current': formatCents(current),
                      'name': line.offer.title,
                      'offer': offer == null ? '—' : formatCents(offer),
                    },
                  );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () {
              final q = Uri(
                path: '/clientes/$clienteId/mensaje',
                queryParameters: {
                  'tpl': 'oferta_suministro',
                  'bloque': bloqueKey,
                  'documento': line.offer.title,
                },
              );
              context.go('${q.path}?${q.query}');
            },
            child: Text('ofertas.draft'.tr()),
          ),
        ],
      ),
    );
  }
}
