import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../core/money/cents.dart';
import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../../core/time/office_date.dart';
import '../settings/office_settings_controller.dart';
import 'factura.dart';
import 'factura_lineas.dart';
import 'factura_print.dart';
import 'factura_print_html.dart';
import 'facturacion_providers.dart';
import 'sif_emit.dart';
import 'sif_qr.dart';

/// Náhled vystavené (papír) nebo zápis přijaté. Tisk jen u emitidas.
class FacturaDetailScreen extends ConsumerStatefulWidget {
  const FacturaDetailScreen({super.key, required this.facturaId});

  final String facturaId;

  @override
  ConsumerState<FacturaDetailScreen> createState() =>
      _FacturaDetailScreenState();
}

class _FacturaDetailScreenState extends ConsumerState<FacturaDetailScreen> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(facturaByIdProvider(widget.facturaId));
    final settings = ref.watch(officeSettingsProvider).valueOrNull;
    return FeatureGate(
      module: GestoriaModule.facturacion,
      fallback: Scaffold(
        body: Center(child: Text('facturacion.moduleOff'.tr())),
      ),
      child: Scaffold(
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(child: Text('facturacion.empty'.tr())),
          data: (row) {
            if (row == null) {
              return Center(child: Text('facturacion.empty'.tr()));
            }
            return ListView(
              children: [
                AppContent(
                  maxWidth: AppTheme.contentWide,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppPageHeader(
                        kicker: settings?.displayName,
                        title: row.refLabel.isEmpty
                            ? 'facturacion.title'.tr()
                            : row.refLabel,
                        subtitle: row.isEmitida
                            ? 'facturacion.detailIssuedHint'.tr()
                            : 'facturacion.detailReceivedHint'.tr(),
                        actions: [
                          OutlinedButton(
                            onPressed: () => context.go(
                              row.isEmitida
                                  ? '/facturacion/emitidas'
                                  : '/facturacion/recibidas',
                            ),
                            child: Text('clients.cancel'.tr()),
                          ),
                          if (row.isEmitida)
                            FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _print(row, settings),
                              icon: const Icon(Icons.print_outlined, size: 18),
                              label: Text('facturacion.print'.tr()),
                            ),
                          if (row.canEmitir)
                            FilledButton(
                              onPressed: _busy ? null : () => _sif(row, false),
                              child: Text('facturacion.emitir'.tr()),
                            ),
                          if (row.canVerificar)
                            OutlinedButton(
                              onPressed: _busy ? null : () => _sif(row, true),
                              child: Text('facturacion.verificar'.tr()),
                            ),
                        ],
                      ),
                      if (row.isEmitida)
                        _IssuedPaper(row: row, settings: settings)
                      else
                        _ReceivedRecord(row: row),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _print(Factura row, OfficeSettings? settings) {
    final html = facturaEmitidaPrintHtml(
      factura: row,
      emisorNombre: (settings?.emisorNombre ?? '').trim().isNotEmpty
          ? settings!.emisorNombre.trim()
          : (settings?.displayName ?? '').trim(),
      emisorNif: (settings?.emisorNif ?? '').trim(),
    );
    printHtmlDocument(html);
  }

  Future<void> _sif(Factura row, bool verify) async {
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    if (tenantId == null) return;
    if (!verify && row.needsDestinatario && !row.hasDestinatario) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('facturacion.destinatarioRequired'.tr())),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final result = verify
          ? await verifyFacturaViaSif(tenantId: tenantId, facturaId: row.id)
          : await emitFacturaViaSif(tenantId: tenantId, facturaId: row.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sifSnackKey(result, verify: verify).tr())),
      );
      ref.invalidate(facturaByIdProvider(row.id));
      ref.invalidate(facturasOfficeProvider);
      if (result.ok) {
        await showSifQrDialog(
          context,
          qrStored: result.sifQrUrl ?? row.sifQrUrl,
          aeatUrl: result.sifAeatUrl ?? row.sifAeatUrl,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _IssuedPaper extends StatelessWidget {
  const _IssuedPaper({required this.row, required this.settings});

  final Factura row;
  final OfficeSettings? settings;

  @override
  Widget build(BuildContext context) {
    final emisorNombre = (settings?.emisorNombre ?? '').trim().isNotEmpty
        ? settings!.emisorNombre.trim()
        : (settings?.displayName ?? '').trim();
    final emisorNif = (settings?.emisorNif ?? '').trim();
    final totals = totalsFromLineas([
      for (final raw in row.lineas) FacturaLinea.fromJson(raw),
    ]);
    final lines = totals.lineas;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              row.isSimplificada ? 'FACTURA SIMPLIFICADA' : 'FACTURA',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('facturacion.emisor'.tr(),
                          style: Theme.of(context).textTheme.titleSmall),
                      Text(emisorNombre.isEmpty ? '—' : emisorNombre),
                      if (emisorNif.isNotEmpty) Text('NIF $emisorNif'),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        row.refLabel,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(toDmyDate(row.fecha) ?? row.fecha ?? ''),
                      if ((row.vencimiento ?? '').isNotEmpty)
                        Text(
                          '${'fields.due'.tr()} ${toDmyDate(row.vencimiento) ?? row.vencimiento}',
                        ),
                      Text(
                        'facturacion.estado.${row.estado}'.tr(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.pencil,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (row.destinatarioNombre != null || row.destinatarioNif != null) ...[
              const SizedBox(height: 20),
              Text('facturacion.destinatario'.tr(),
                  style: Theme.of(context).textTheme.titleSmall),
              Text(row.destinatarioNombre ?? ''),
              if (row.destinatarioNif != null) Text('NIF ${row.destinatarioNif}'),
              if (row.destinatarioDireccion != null)
                Text(row.destinatarioDireccion!),
              if (row.destinatarioEmail != null) Text(row.destinatarioEmail!),
            ],
            const SizedBox(height: 20),
            if (lines.isEmpty)
              Text(
                '${formatCents(row.totalCents)} € · ${row.concepto ?? ''}',
                style: Theme.of(context).textTheme.titleMedium,
              )
            else ...[
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(line.descripcion)),
                      Text(
                        '${cantidadString(line.cantidad)} × ${formatCents(line.precioUnitarioCents)} €',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.pencil,
                            ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 88,
                        child: Text(
                          '${formatCents(line.totalCents)} €',
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(),
              for (final tax in totals.byRate)
                _Amt(
                  label: '${'fields.iva'.tr()} ${ivaRateLabel(tax.ivaBps)}',
                  value: tax.ivaCents,
                ),
              _Amt(label: 'facturacion.grandTotal'.tr(), value: totals.totalCents),
            ],
            if ((row.concepto ?? '').isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(row.concepto!),
            ],
            if ((row.notas ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                row.notas!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.pencil,
                    ),
              ),
            ],
            if (row.formaPago != null) ...[
              const SizedBox(height: 8),
              Text(
                '${'facturacion.formaPago'.tr()}: ${'facturacion.pago.${row.formaPago}'.tr()}',
              ),
            ],
            if ((row.sifQrUrl ?? '').isNotEmpty ||
                (row.sifAeatUrl ?? '').isNotEmpty) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => showSifQrDialog(
                    context,
                    qrStored: row.sifQrUrl,
                    aeatUrl: row.sifAeatUrl,
                  ),
                  icon: const Icon(Icons.qr_code_2_outlined, size: 18),
                  label: Text('facturacion.qr'.tr()),
                ),
              ),
            ],
            if (row.clienteId != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.go('/clientes/${row.clienteId}'),
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: Text('nav.clients'.tr()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReceivedRecord extends StatelessWidget {
  const _ReceivedRecord({required this.row});

  final Factura row;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'facturacion.received'.tr(),
      hint: 'facturacion.detailReceivedHint'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${formatCents(row.totalCents)} €',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(row.proveedorNombre ?? row.counterparty),
          if (row.proveedorNif != null) Text('NIF ${row.proveedorNif}'),
          if (row.numero != null) Text(row.numero!),
          if (row.fecha != null) Text(toDmyDate(row.fecha) ?? row.fecha!),
          if (row.concepto != null) Text(row.concepto!),
          const SizedBox(height: 12),
          _Amt(label: 'fields.base'.tr(), value: row.baseCents),
          _Amt(label: 'fields.iva'.tr(), value: row.ivaCents),
          _Amt(label: 'facturacion.grandTotal'.tr(), value: row.totalCents),
          if (row.clienteId != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => context.go('/clientes/${row.clienteId}'),
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: Text('facturacion.openCarpeta'.tr()),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Amt extends StatelessWidget {
  const _Amt({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text('${formatCents(value)} €'),
        ],
      ),
    );
  }
}
