import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../core/documents/office_attach_button.dart';
import '../../core/money/cents.dart';
import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/theme/app_theme.dart';
import '../clientes/cliente_card_widgets.dart';
import 'factura.dart';
import 'facturacion_providers.dart';

/// Slot `cliente.tabs`: vydané i přijaté u karty. Guardar přijaté zůstává u papíru.
class ClienteFacturasSection extends ConsumerWidget {
  const ClienteFacturasSection({super.key, required this.clienteId});

  final String clienteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(facturasClienteProvider(clienteId));
    final rows = async.valueOrNull ?? const [];
    final issued = rows.where((r) => r.isEmitida).toList();
    final received = rows.where((r) => r.isRecibida).toList();
    final tenantId =
        ref.watch(authControllerProvider).valueOrNull?.currentTenantId;
    return FeatureGate(
      module: GestoriaModule.facturacion,
      child: ClienteCardSection(
        title: 'facturacion.title'.tr(),
        hint: 'facturacion.cardHint'.tr(),
        trailing: tenantId == null
            ? null
            : OfficeAttachButton(
                outlined: true,
                label: 'docs.factura_recibida'.tr(),
                onPicked: (file) async {
                  await attachFacturaRecibida(
                    tenantId: tenantId,
                    clienteId: clienteId,
                    bytes: file.bytes,
                    originalName: file.name,
                    createdBy: ref
                        .read(authControllerProvider)
                        .valueOrNull
                        ?.profile
                        ?.id,
                  );
                  ref.invalidate(facturasClienteProvider(clienteId));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('facturacion.extractPending'.tr())),
                    );
                  }
                },
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (async.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              )
            else ...[
              Text(
                'facturacion.issuedOnCard'.tr(),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (issued.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 12),
                  child: Text(
                    'facturacion.emptyIssuedCliente'.tr(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.pencil,
                        ),
                  ),
                )
              else
                for (final row in issued) _rowTile(context, row),
              Text(
                'facturacion.received'.tr(),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (received.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'facturacion.emptyCliente'.tr(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.pencil,
                        ),
                  ),
                )
              else
                for (final row in received) _rowTile(context, row),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rowTile(BuildContext context, Factura row) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        [
          if (row.refLabel.isNotEmpty) row.refLabel,
          '${formatCents(row.totalCents)} €',
        ].join(' · '),
      ),
      subtitle: Text(
        [
          if ((row.fecha ?? '').isNotEmpty) row.fecha,
          if (row.counterparty.isNotEmpty) row.counterparty,
          'facturacion.estado.${row.estado}'.tr(),
        ].join(' · '),
      ),
      onTap: () => context.go(
        row.isEmitida ? '/facturacion/f/${row.id}' : '/facturacion/recibidas',
      ),
    );
  }
}
