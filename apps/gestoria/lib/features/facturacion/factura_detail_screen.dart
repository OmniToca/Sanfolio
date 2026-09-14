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
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => context.go(
                            row.isEmitida
                                ? '/facturacion/emitidas'
                                : '/facturacion/recibidas',
                          ),
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: Text('facturacion.backToList'.tr()),
                        ),
                      ),
                      AppPageHeader(
                        kicker: settings?.displayName,
                        title: row.refLabel.isEmpty
                            ? 'facturacion.title'.tr()
                            : row.refLabel,
                        subtitle: row.isEmitida
                            ? 'facturacion.detailIssuedHint'.tr()
                            : 'facturacion.detailReceivedHint'.tr(),
                        actions: [
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
                        bottom: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _ReadStamp(
                              label: 'facturacion.estado.${row.estado}'.tr(),
                              selected: row.estado == 'emitida',
                            ),
                            _ReadStamp(
                              label: row.isSimplificada
                                  ? 'facturacion.tipoF2'.tr()
                                  : 'facturacion.tipoF1'.tr(),
                              selected: true,
                            ),
                          ],
                        ),
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

class _ReadStamp extends StatelessWidget {
  const _ReadStamp({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? AppTheme.accentSoft : AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.rule),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
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
    final overdue = row.isVencida();
    final clientName = (row.destinatarioNombre ?? row.clienteNombre ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (clientName.isNotEmpty) ...[
          Text(clientName, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              if ((row.destinatarioNif ?? '').isNotEmpty)
                Text('NIF ${row.destinatarioNif}'),
              if ((row.destinatarioEmail ?? '').isNotEmpty)
                Text(row.destinatarioEmail!),
              if ((row.destinatarioDireccion ?? '').isNotEmpty)
                Text(row.destinatarioDireccion!),
            ],
          ),
          const SizedBox(height: 16),
        ],
        _threeCol(
          _InfoCard(
            title: 'facturacion.datesCard'.tr(),
            children: [
              _kv(
                context,
                'facturacion.issuedDate'.tr(),
                toDmyDate(row.fecha) ?? row.fecha ?? '—',
              ),
              _kv(
                context,
                'fields.due'.tr(),
                toDmyDate(row.vencimiento) ?? row.vencimiento ?? '—',
                valueColor: overdue ? AppTheme.urgent : null,
              ),
            ],
          ),
          _InfoCard(
            title: 'facturacion.taxCard'.tr(),
            children: [
              _kv(
                context,
                'facturacion.colTipo'.tr(),
                row.isSimplificada
                    ? 'facturacion.tipoF2'.tr()
                    : 'facturacion.tipoF1'.tr(),
              ),
              _kv(
                context,
                'fields.iva'.tr(),
                lines.isEmpty
                    ? ivaRateLabel(row.ivaBps ?? 2100)
                    : lines.map((l) => ivaRateLabel(l.ivaBps)).toSet().join(' · '),
              ),
              _kv(context, 'facturacion.emisor'.tr(), emisorNombre.isEmpty ? '—' : emisorNombre),
              if (emisorNif.isNotEmpty) _kv(context, 'NIF', emisorNif),
            ],
          ),
          _InfoCard(
            title: 'facturacion.payCard'.tr(),
            children: [
              _kv(
                context,
                'facturacion.formaPago'.tr(),
                row.formaPago == null
                    ? '—'
                    : 'facturacion.pago.${row.formaPago}'.tr(),
              ),
              _kv(
                context,
                'facturacion.colEstado'.tr(),
                'facturacion.estado.${row.estado}'.tr(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppSectionCard(
          title: 'facturacion.lineas'.tr(),
          child: lines.isEmpty
              ? Text(
                  '${formatCents(row.totalCents)} € · ${row.concepto ?? ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                )
              : _LinesTable(lines: lines),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AppSectionCard(
              title: 'facturacion.totals'.tr(),
              child: Column(
                children: [
                  if (totals.byRate.isEmpty) ...[
                    _Amt(label: 'facturacion.baseExcl'.tr(), value: row.baseCents),
                    _Amt(label: 'facturacion.ivaTotal'.tr(), value: row.ivaCents),
                  ] else
                    for (final tax in totals.byRate) ...[
                      _Amt(
                        label: '${'fields.base'.tr()} ${ivaRateLabel(tax.ivaBps)}',
                        value: tax.baseCents,
                      ),
                      _Amt(
                        label: '${'fields.iva'.tr()} ${ivaRateLabel(tax.ivaBps)}',
                        value: tax.ivaCents,
                      ),
                    ],
                  const Divider(),
                  _Amt(
                    label: 'facturacion.grandTotal'.tr(),
                    value: totals.lineas.isNotEmpty
                        ? totals.totalCents
                        : row.totalCents,
                    emphasize: true,
                  ),
                ],
              ),
            ),
          ),
        ),
        if ((row.concepto ?? '').isNotEmpty || (row.notas ?? '').isNotEmpty) ...[
          const SizedBox(height: 16),
          AppSectionCard(
            title: 'fields.concept'.tr(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((row.concepto ?? '').isNotEmpty) Text(row.concepto!),
                if ((row.notas ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    row.notas!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.pencil,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        AppSectionCard(
          title: 'facturacion.verifactuTitle'.tr(),
          hint: 'facturacion.verifactuHint'.tr(),
          child: Align(
            alignment: Alignment.centerLeft,
            child: (row.sifQrUrl ?? '').isNotEmpty ||
                    (row.sifAeatUrl ?? '').isNotEmpty
                ? TextButton.icon(
                    onPressed: () => showSifQrDialog(
                      context,
                      qrStored: row.sifQrUrl,
                      aeatUrl: row.sifAeatUrl,
                    ),
                    icon: const Icon(Icons.qr_code_2_outlined, size: 18),
                    label: Text('facturacion.qr'.tr()),
                  )
                : Text(
                    'facturacion.issuedHint'.tr(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
          ),
        ),
        if (row.clienteId != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.go('/clientes/${row.clienteId}'),
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: Text('nav.clients'.tr()),
            ),
          ),
        ],
      ],
    );
  }
}

Widget _threeCol(Widget a, Widget b, Widget c) {
  return LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 800) {
        return Column(
          children: [
            a,
            const SizedBox(height: 8),
            b,
            const SizedBox(height: 8),
            c,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: 8),
          Expanded(child: b),
          const SizedBox(width: 8),
          Expanded(child: c),
        ],
      );
    },
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

Widget _kv(
  BuildContext context,
  String label,
  String value, {
  Color? valueColor,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: valueColor,
                  fontWeight: valueColor == null ? null : FontWeight.w600,
                ),
          ),
        ),
      ],
    ),
  );
}

class _LinesTable extends StatelessWidget {
  const _LinesTable({required this.lines});

  final List<FacturaLinea> lines;

  @override
  Widget build(BuildContext context) {
    final head = Theme.of(context).textTheme.titleSmall;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(flex: 5, child: Text('facturacion.descripcion'.tr(), style: head)),
              Expanded(
                flex: 1,
                child: Text(
                  'facturacion.colCant'.tr(),
                  style: head,
                  textAlign: TextAlign.right,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'facturacion.colPrecio'.tr(),
                  style: head,
                  textAlign: TextAlign.right,
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  'facturacion.colIva'.tr(),
                  style: head,
                  textAlign: TextAlign.right,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'facturacion.colImporte'.tr(),
                  style: head,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        for (final line in lines) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(flex: 5, child: Text(line.descripcion)),
                Expanded(
                  flex: 1,
                  child: Text(
                    cantidadString(line.cantidad),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${formatCents(line.precioUnitarioCents)} €',
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    ivaRateLabel(line.ivaBps),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${formatCents(line.totalCents)} €',
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
        ],
      ],
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
  const _Amt({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final int value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text('${formatCents(value)} €', style: style),
        ],
      ),
    );
  }
}
