import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../core/documents/office_attach_button.dart';
import '../../core/money/cents.dart';
import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../../core/time/office_date.dart';
import '../carpeta/carpeta_controller.dart';
import '../settings/office_settings_controller.dart';
import 'csv_save.dart';
import 'factura.dart';
import 'factura_cliente_pick.dart';
import 'factura_kpi.dart';
import 'factura_print.dart';
import 'factura_print_html.dart';
import 'factura_status.dart';
import 'facturacion_nav.dart';
import 'facturacion_providers.dart';
import 'sif_emit.dart';
import 'sif_qr.dart';

class FacturacionScreen extends ConsumerStatefulWidget {
  const FacturacionScreen({super.key, this.libroKey = 'emitidas'});

  final String libroKey;

  @override
  ConsumerState<FacturacionScreen> createState() => _FacturacionScreenState();
}

class _FacturacionScreenState extends ConsumerState<FacturacionScreen> {
  bool _busy = false;

  FacturacionLibro get _libro =>
      facturacionLibroByKey(widget.libroKey) ?? kFacturacionLibros.first;

  @override
  Widget build(BuildContext context) {
    final office =
        ref.watch(officeSettingsProvider).valueOrNull?.displayName ?? '';
    return FeatureGate(
      module: GestoriaModule.facturacion,
      fallback: Scaffold(
        body: Center(child: Text('facturacion.moduleOff'.tr())),
      ),
      child: Scaffold(
        appBar: AppBar(title: Text('facturacion.title'.tr())),
        body: _BookTab(
          libro: _libro,
          office: office,
          busy: _busy,
          onAdd: _libro.isCompras ? _addReceived : _addIssued,
          onCsv: _exportCsv,
          onHide: _hide,
          onEmit: _libro.isVentas ? _emit : null,
          onVerify: _libro.isVentas ? _verify : null,
        ),
      ),
    );
  }

  Future<void> _exportCsv() async {
    final rows =
        ref.read(facturasOfficeProvider(_libro.direccion)).valueOrNull ??
            const [];
    if (_libro.isCompras) {
      saveCsvFile('facturas-recibidas.csv', receivedInvoicesCsv(rows));
    } else {
      saveCsvFile('facturas-emitidas.csv', issuedInvoicesCsv(rows));
    }
  }

  Future<void> _hide(String id) async {
    setState(() => _busy = true);
    try {
      await hideFactura(id);
      ref.invalidate(facturasOfficeProvider);
      ref.invalidate(facturasClienteProvider);
      ref.invalidate(carpetaControllerProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addReceived() async {
    final picked = await showDialog<FacturaClientePick>(
      context: context,
      builder: (ctx) => const FacturaClientePickDialog(),
    );
    if (picked == null || !mounted) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('facturacion.attachReceived'.tr()),
          content: Text(
            'facturacion.attachReceivedHint'.tr(
              namedArgs: {'name': picked.nombre},
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('clients.cancel'.tr()),
            ),
            OfficeAttachButton(
              outlined: false,
              label: 'facturacion.pickPdf'.tr(),
              onPicked: (file) async {
                Navigator.pop(ctx);
                await _uploadReceived(picked, file.bytes, file.name);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _uploadReceived(
    FacturaClientePick picked,
    Uint8List bytes,
    String name,
  ) async {
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    if (tenantId == null) return;
    setState(() => _busy = true);
    try {
      await attachFacturaRecibida(
        tenantId: tenantId,
        clienteId: picked.id,
        bytes: bytes,
        originalName: name,
        createdBy: ref.read(authControllerProvider).valueOrNull?.profile?.id,
      );
      if (!mounted) return;
      context.go('/clientes/${picked.id}');
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('folder.uploadError'.tr(namedArgs: {'code': ''})),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addIssued() async {
    context.go('/facturacion/nueva');
  }

  Future<void> _emit(Factura row) async {
    if (row.needsDestinatario && !row.hasDestinatario) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('facturacion.destinatarioRequired'.tr())),
      );
      return;
    }
    await _sifCall(row, verify: false);
  }

  Future<void> _verify(Factura row) async {
    await _sifCall(row, verify: true);
  }

  Future<void> _sifCall(Factura row, {required bool verify}) async {
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    if (tenantId == null) return;
    setState(() => _busy = true);
    try {
      final result = verify
          ? await verifyFacturaViaSif(
              tenantId: tenantId,
              facturaId: row.id,
            )
          : await emitFacturaViaSif(
              tenantId: tenantId,
              facturaId: row.id,
            );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sifSnackKey(result, verify: verify).tr())),
      );
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

class _BookTab extends ConsumerStatefulWidget {
  const _BookTab({
    required this.libro,
    required this.office,
    required this.busy,
    required this.onAdd,
    required this.onHide,
    this.onCsv,
    this.onEmit,
    this.onVerify,
  });

  final FacturacionLibro libro;
  final String office;
  final bool busy;
  final VoidCallback onAdd;
  final Future<void> Function(String id) onHide;
  final VoidCallback? onCsv;
  final Future<void> Function(Factura row)? onEmit;
  final Future<void> Function(Factura row)? onVerify;

  @override
  ConsumerState<_BookTab> createState() => _BookTabState();
}

class _BookTabState extends ConsumerState<_BookTab> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final libro = widget.libro;
    final async = ref.watch(facturasOfficeProvider(libro.direccion));
    final settings = ref.watch(officeSettingsProvider).valueOrNull;
    final rows = async.valueOrNull ?? const <Factura>[];
    final filtered = rows.where((r) => r.matchesQuery(_query.text)).toList();
    final kpi = libroKpi(
      rows,
      today: DateTime.now(),
      emitidas: libro.isVentas,
    );
    final sections = facturacionLibrosIn(libro.group);
    final groups = _groupByMonth(context, filtered);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppTheme.contentWide),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppPageHeader(
                  kicker: widget.office.isEmpty ? null : widget.office,
                  title: 'facturacion.libro.${libro.key}'.tr(),
                  subtitle: 'facturacion.libroHint'.tr(),
                  actions: [
                    if (widget.onCsv != null)
                      OutlinedButton.icon(
                        onPressed: rows.isEmpty ? null : widget.onCsv,
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: Text('facturacion.exportCsv'.tr()),
                      ),
                    FilledButton.icon(
                      onPressed: widget.busy ? null : widget.onAdd,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(
                        libro.isCompras
                            ? 'facturacion.addReceived'.tr()
                            : 'facturacion.addIssued'.tr(),
                      ),
                    ),
                  ],
                  bottom: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final group in facturacionGroups())
                            AppStamp(
                              label: 'facturacion.group.$group'.tr(),
                              selected: libro.group == group,
                              onTap: () {
                                final first = facturacionLibrosIn(group).first;
                                context.go('/facturacion/${first.key}');
                              },
                            ),
                        ],
                      ),
                      if (sections.length > 1) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final section in sections)
                              AppStamp(
                                label: 'facturacion.libro.${section.key}'.tr(),
                                selected: section.key == libro.key,
                                onTap: () =>
                                    context.go('/facturacion/${section.key}'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _KpiRow(kpi: kpi, emitidas: libro.isVentas),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'facturacion.searchHint'.tr(),
                  controller: _query,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  'facturacion.listCount'.tr(
                    namedArgs: {'n': '${filtered.length}'},
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (async.isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (filtered.isEmpty)
                  AppSectionCard(
                    hint: 'facturacion.empty'.tr(),
                    child: const SizedBox.shrink(),
                  )
                else
                  for (final group in groups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                      child: Text(
                        '${group.label} · ${group.rows.length}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    _InvoiceTable(
                      rows: group.rows,
                      ventas: libro.isVentas,
                      busy: widget.busy,
                      onOpen: (row) => context.go('/facturacion/f/${row.id}'),
                      onHide: (row) => widget.onHide(row.id),
                      onEmit: widget.onEmit,
                      onVerify: widget.onVerify,
                      onPrint: libro.isVentas
                          ? (row) => _print(row, settings)
                          : null,
                    ),
                  ],
              ],
            ),
          ),
        ),
      ],
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
}

List<({String label, List<Factura> rows})> _groupByMonth(
  BuildContext context,
  List<Factura> rows,
) {
  final map = <String, List<Factura>>{};
  final labels = <String, String>{};
  for (final row in rows) {
    final d = parseOfficeDate(row.fecha ?? '');
    final key = d == null
        ? ''
        : '${d.year}-${d.month.toString().padLeft(2, '0')}';
    map.putIfAbsent(key, () => []).add(row);
    labels[key] = d == null
        ? 'facturacion.ungrouped'.tr()
        : DateFormat.yMMMM(context.locale.toString()).format(d);
  }
  final keys = map.keys.toList()
    ..sort((a, b) {
      if (a.isEmpty) return 1;
      if (b.isEmpty) return -1;
      return b.compareTo(a);
    });
  return [
    for (final k in keys) (label: labels[k]!, rows: map[k]!),
  ];
}

class _InvoiceTable extends StatelessWidget {
  const _InvoiceTable({
    required this.rows,
    required this.ventas,
    required this.busy,
    required this.onOpen,
    required this.onHide,
    this.onEmit,
    this.onVerify,
    this.onPrint,
  });

  final List<Factura> rows;
  final bool ventas;
  final bool busy;
  final ValueChanged<Factura> onOpen;
  final ValueChanged<Factura> onHide;
  final Future<void> Function(Factura row)? onEmit;
  final Future<void> Function(Factura row)? onVerify;
  final ValueChanged<Factura>? onPrint;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 920;
          return Column(
            children: [
              if (wide) _TableHead(ventas: ventas),
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1),
                _TableRow(
                  row: rows[i],
                  ventas: ventas,
                  wide: wide,
                  busy: busy,
                  onOpen: () => onOpen(rows[i]),
                  onHide: () => onHide(rows[i]),
                  onEmit: onEmit == null || !rows[i].canEmitir
                      ? null
                      : () => onEmit!(rows[i]),
                  onVerify: onVerify == null || !rows[i].canVerificar
                      ? null
                      : () => onVerify!(rows[i]),
                  onPrint: onPrint == null || !rows[i].isEmitida
                      ? null
                      : () => onPrint!(rows[i]),
                ),
              ],
            ],
          );
        },
      ),
      ),
    );
  }
}

class _TableHead extends StatelessWidget {
  const _TableHead({required this.ventas});

  final bool ventas;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall;
    return Container(
      color: AppTheme.surfaceMuted,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Expanded(flex: 12, child: Text('facturacion.colNumero'.tr(), style: style)),
          Expanded(flex: 28, child: Text('facturacion.colCliente'.tr(), style: style)),
          if (ventas)
            Expanded(flex: 10, child: Text('facturacion.colTipo'.tr(), style: style)),
          Expanded(flex: 12, child: Text('facturacion.colFecha'.tr(), style: style)),
          Expanded(flex: 12, child: Text('facturacion.colVencimiento'.tr(), style: style)),
          Expanded(
            flex: 12,
            child: Text(
              'facturacion.colImporte'.tr(),
              style: style,
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(flex: 14, child: Text('facturacion.colEstado'.tr(), style: style)),
          const SizedBox(width: 148),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.row,
    required this.ventas,
    required this.wide,
    required this.busy,
    required this.onOpen,
    required this.onHide,
    this.onEmit,
    this.onVerify,
    this.onPrint,
  });

  final Factura row;
  final bool ventas;
  final bool wide;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onHide;
  final VoidCallback? onEmit;
  final VoidCallback? onVerify;
  final VoidCallback? onPrint;

  @override
  Widget build(BuildContext context) {
    final overdue = row.isVencida();
    final dueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: overdue ? AppTheme.urgent : null,
          fontWeight: overdue ? FontWeight.w600 : null,
        );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onPrint != null)
          IconButton(
            tooltip: 'facturacion.print'.tr(),
            visualDensity: VisualDensity.compact,
            onPressed: busy ? null : onPrint,
            icon: const Icon(Icons.print_outlined, size: 18),
          ),
        if (onEmit != null)
          IconButton(
            tooltip: 'facturacion.emitir'.tr(),
            visualDensity: VisualDensity.compact,
            onPressed: busy ? null : onEmit,
            icon: const Icon(Icons.send_outlined, size: 18),
          ),
        if (onVerify != null)
          IconButton(
            tooltip: 'facturacion.verificar'.tr(),
            visualDensity: VisualDensity.compact,
            onPressed: busy ? null : onVerify,
            icon: const Icon(Icons.verified_outlined, size: 18),
          ),
        IconButton(
          tooltip: 'clients.softDelete'.tr(),
          visualDensity: VisualDensity.compact,
          onPressed: busy ? null : onHide,
          icon: const Icon(Icons.visibility_off_outlined, size: 18),
        ),
      ],
    );
    if (!wide) {
      return InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.refLabel.isEmpty ? '—' : row.refLabel,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      row.counterparty.isEmpty ? '—' : row.counterparty,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if ((row.concepto ?? '').isNotEmpty)
                      Text(
                        row.concepto!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.pencil,
                            ),
                      ),
                    Row(
                      children: [
                        FacturaEstadoDot(estado: row.estado),
                        const SizedBox(width: 6),
                        Text(
                          'facturacion.estado.${row.estado}'.tr(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${formatCents(row.totalCents)} €',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if ((row.vencimiento ?? '').isNotEmpty)
                    Text(
                      toDmyDate(row.vencimiento) ?? row.vencimiento!,
                      style: dueStyle,
                    ),
                ],
              ),
              actions,
            ],
          ),
        ),
      );
    }
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              flex: 12,
              child: Text(
                row.refLabel.isEmpty ? '—' : row.refLabel,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              flex: 28,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.counterparty.isEmpty ? '—' : row.counterparty,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((row.concepto ?? '').isNotEmpty)
                    Text(
                      row.concepto!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.pencil,
                          ),
                    ),
                ],
              ),
            ),
            if (ventas)
              Expanded(
                flex: 10,
                child: Text(
                  row.isSimplificada
                      ? 'facturacion.tipoF2'.tr()
                      : 'facturacion.tipoF1'.tr(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Expanded(
              flex: 12,
              child: Text(toDmyDate(row.fecha) ?? row.fecha ?? '—'),
            ),
            Expanded(
              flex: 12,
              child: Text(
                toDmyDate(row.vencimiento) ?? row.vencimiento ?? '—',
                style: dueStyle,
              ),
            ),
            Expanded(
              flex: 12,
              child: Text(
                '${formatCents(row.totalCents)} €',
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              flex: 14,
              child: Row(
                children: [
                  FacturaEstadoDot(estado: row.estado),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'facturacion.estado.${row.estado}'.tr(),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 148, child: actions),
          ],
        ),
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.kpi, required this.emitidas});

  final LibroKpi kpi;
  final bool emitidas;

  @override
  Widget build(BuildContext context) {
    final fourthLabel = emitidas
        ? 'facturacion.kpiPending'.tr()
        : 'facturacion.kpiDueSoon'.tr();
    final fourthValue = emitidas ? '${kpi.pendingCount}' : '${kpi.dueSoonCount}';
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 720;
        final cards = [
          _KpiCard(
            label: 'facturacion.kpiImporte'.tr(
              namedArgs: {'year': '${kpi.year}'},
            ),
            value: '${formatCents(kpi.totalCents)} €',
          ),
          _KpiCard(
            label: emitidas
                ? 'facturacion.kpiIssued'.tr()
                : 'facturacion.kpiReceived'.tr(),
            value: '${kpi.count}',
          ),
          _KpiCard(
            label: 'facturacion.kpiOverdue'.tr(),
            value: '${kpi.overdueCount}',
            hint: '${formatCents(kpi.overdueCents)} €',
          ),
          _KpiCard(
            label: fourthLabel,
            value: fourthValue,
          ),
        ];
        if (!wide) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                cards[i],
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    this.hint,
  });

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            if (hint != null)
              Text(
                hint!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.pencil,
                    ),
              ),
          ],
        ),
      ),
    );
  }
}
