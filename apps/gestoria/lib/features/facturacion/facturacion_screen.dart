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
import '../settings/office_settings_controller.dart';
import 'csv_save.dart';
import 'factura.dart';
import 'factura_cliente_pick.dart';
import 'facturacion_providers.dart';
import 'sif_emit.dart';
import 'sif_qr.dart';

class FacturacionScreen extends ConsumerStatefulWidget {
  const FacturacionScreen({super.key});

  @override
  ConsumerState<FacturacionScreen> createState() => _FacturacionScreenState();
}

class _FacturacionScreenState extends ConsumerState<FacturacionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

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
        appBar: AppBar(
          title: Text('facturacion.title'.tr()),
          bottom: TabBar(
            controller: _tabs,
            tabs: [
              Tab(text: 'facturacion.received'.tr()),
              Tab(text: 'facturacion.issued'.tr()),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _BookTab(
              direccion: 'recibida',
              office: office,
              busy: _busy,
              onAdd: _addReceived,
              onCsv: _exportCsv,
              onHide: _hide,
            ),
            _BookTab(
              direccion: 'emitida',
              office: office,
              busy: _busy,
              onAdd: _addIssued,
              onEmit: _emit,
              onVerify: _verify,
              onHide: _hide,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCsv() async {
    final rows =
        ref.read(facturasOfficeProvider('recibida')).valueOrNull ?? const [];
    saveCsvFile(
      'facturas-recibidas.csv',
      receivedInvoicesCsv(rows),
    );
  }

  Future<void> _hide(String id) async {
    setState(() => _busy = true);
    try {
      await hideFactura(id);
      ref.invalidate(facturasOfficeProvider);
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

class _BookTab extends ConsumerWidget {
  const _BookTab({
    required this.direccion,
    required this.office,
    required this.busy,
    required this.onAdd,
    required this.onHide,
    this.onCsv,
    this.onEmit,
    this.onVerify,
  });

  final String direccion;
  final String office;
  final bool busy;
  final VoidCallback onAdd;
  final Future<void> Function(String id) onHide;
  final VoidCallback? onCsv;
  final Future<void> Function(Factura row)? onEmit;
  final Future<void> Function(Factura row)? onVerify;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(facturasOfficeProvider(direccion));
    final rows = async.valueOrNull ?? const <Factura>[];
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
                  kicker: office.isEmpty ? null : office,
                  title: direccion == 'recibida'
                      ? 'facturacion.received'.tr()
                      : 'facturacion.issued'.tr(),
                  subtitle: direccion == 'recibida'
                      ? 'facturacion.receivedHint'.tr()
                      : 'facturacion.issuedHint'.tr(),
                  actions: [
                    if (onCsv != null)
                      OutlinedButton.icon(
                        onPressed: rows.isEmpty ? null : onCsv,
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: Text('facturacion.exportCsv'.tr()),
                      ),
                    FilledButton.icon(
                      onPressed: busy ? null : onAdd,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(
                        direccion == 'recibida'
                            ? 'facturacion.addReceived'.tr()
                            : 'facturacion.addIssued'.tr(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (async.isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (rows.isEmpty)
                  AppSectionCard(
                    hint: 'facturacion.empty'.tr(),
                    child: const SizedBox.shrink(),
                  )
                else
                  for (final row in rows) ...[
                    _FacturaTile(
                      row: row,
                      busy: busy,
                      onHide: () => onHide(row.id),
                      onEmit: onEmit == null || !row.canEmitir
                          ? null
                          : () => onEmit!(row),
                      onVerify: onVerify == null || !row.canVerificar
                          ? null
                          : () => onVerify!(row),
                      onQr: (row.sifQrUrl ?? '').isEmpty &&
                              (row.sifAeatUrl ?? '').isEmpty
                          ? null
                          : () => showSifQrDialog(
                                context,
                                qrStored: row.sifQrUrl,
                                aeatUrl: row.sifAeatUrl,
                              ),
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FacturaTile extends StatelessWidget {
  const _FacturaTile({
    required this.row,
    required this.busy,
    required this.onHide,
    this.onEmit,
    this.onVerify,
    this.onQr,
  });

  final Factura row;
  final bool busy;
  final VoidCallback onHide;
  final VoidCallback? onEmit;
  final VoidCallback? onVerify;
  final VoidCallback? onQr;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if ((row.fecha ?? '').isNotEmpty) row.fecha,
      if ((row.serie ?? '').isNotEmpty || (row.numero ?? '').isNotEmpty)
        [row.serie, row.numero].where((s) => (s ?? '').isNotEmpty).join('-'),
      if (row.counterparty.isNotEmpty) row.counterparty,
    ].join(' · ');
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${formatCents(row.totalCents)} €',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.pencil,
                          ),
                    ),
                  Text(
                    'facturacion.estado.${row.estado}'.tr(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.pencil,
                        ),
                  ),
                  if ((row.sifStatus ?? '').isNotEmpty &&
                      row.sifStatus != row.estado)
                    Text(
                      row.sifStatus!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppTheme.pencil,
                          ),
                    ),
                ],
              ),
            ),
            if (row.clienteId != null)
              IconButton(
                tooltip: 'nav.clients'.tr(),
                onPressed: () =>
                    context.go('/clientes/${row.clienteId}'),
                icon: const Icon(Icons.folder_open_outlined),
              ),
            if (onQr != null)
              IconButton(
                tooltip: 'facturacion.qr'.tr(),
                onPressed: busy ? null : onQr,
                icon: const Icon(Icons.qr_code_2_outlined),
              ),
            if (onEmit != null)
              TextButton(
                onPressed: busy ? null : onEmit,
                child: Text('facturacion.emitir'.tr()),
              ),
            if (onVerify != null)
              TextButton(
                onPressed: busy ? null : onVerify,
                child: Text('facturacion.verificar'.tr()),
              ),
            IconButton(
              tooltip: 'clients.softDelete'.tr(),
              onPressed: busy ? null : onHide,
              icon: const Icon(Icons.visibility_off_outlined),
            ),
          ],
        ),
      ),
    );
  }
}
