import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../core/documents/office_attach_button.dart';
import '../../core/identity/nie_persist.dart';
import '../../core/money/cents.dart';
import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../settings/office_settings_controller.dart';
import 'csv_save.dart';
import 'factura.dart';
import 'facturacion_providers.dart';
import 'sif_emit.dart';

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
    final picked = await showDialog<_PickedCliente>(
      context: context,
      builder: (ctx) => const _ClientePickDialog(),
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
    _PickedCliente picked,
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
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    if (tenantId == null) return;
    final settings = ref.read(officeSettingsProvider).valueOrNull;
    final serie = (settings?.facturaSerie ?? 'A').trim().isEmpty
        ? 'A'
        : settings!.facturaSerie.trim();
    final n = await nextFacturaNumero(tenantId: tenantId, serie: serie);
    if (!mounted) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => _IssuedDraftDialog(
        tenantId: tenantId,
        serie: serie,
        numero: '$n',
      ),
    );
    if (created == true) {
      ref.invalidate(facturasOfficeProvider);
    }
  }

  Future<void> _emit(Factura row) async {
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    if (tenantId == null) return;
    setState(() => _busy = true);
    try {
      final result = await emitFacturaViaSif(
        tenantId: tenantId,
        facturaId: row.id,
      );
      if (!mounted) return;
      final key = result.ok
          ? 'facturacion.emitOk'
          : result.error == 'sif_not_configured'
              ? 'facturacion.sifNotConfigured'
              : result.error == 'emisor_nif_required'
                  ? 'facturacion.emisorNifRequired'
                  : 'facturacion.emitError';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(key.tr())),
      );
      ref.invalidate(facturasOfficeProvider);
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
  });

  final String direccion;
  final String office;
  final bool busy;
  final VoidCallback onAdd;
  final Future<void> Function(String id) onHide;
  final VoidCallback? onCsv;
  final Future<void> Function(Factura row)? onEmit;

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
  });

  final Factura row;
  final bool busy;
  final VoidCallback onHide;
  final VoidCallback? onEmit;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if ((row.fecha ?? '').isNotEmpty) row.fecha,
      if ((row.numero ?? '').isNotEmpty) row.numero,
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
            if (onEmit != null)
              TextButton(
                onPressed: busy ? null : onEmit,
                child: Text('facturacion.emitir'.tr()),
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

class _PickedCliente {
  const _PickedCliente({required this.id, required this.nombre, this.nie});

  final String id;
  final String nombre;
  final String? nie;
}

class _ClientePickDialog extends ConsumerStatefulWidget {
  const _ClientePickDialog();

  @override
  ConsumerState<_ClientePickDialog> createState() => _ClientePickDialogState();
}

class _ClientePickDialogState extends ConsumerState<_ClientePickDialog> {
  final _q = TextEditingController();
  List<_PickedCliente> _all = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    final client = trySupabaseClient();
    if (tenantId == null || client == null) {
      setState(() => _loading = false);
      return;
    }
    final rows = await client
        .from('clientes')
        .select(
          'id, nombre, client_identifiers(kind, value_raw, deleted_at)',
        )
        .eq('tenant_id', tenantId)
        .isFilter('deleted_at', null)
        .eq('status', 'activo')
        .order('nombre')
        .limit(80);
    final out = <_PickedCliente>[];
    for (final raw in rows) {
      final nombre = '${raw['nombre'] ?? ''}'.trim();
      if (nombre.isEmpty) continue;
      out.add(
        _PickedCliente(
          id: '${raw['id']}',
          nombre: nombre,
          nie: preferredFiscalRawFromRows(raw['client_identifiers']),
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      _all = out;
      _loading = false;
    });
  }

  List<_PickedCliente> get _filtered {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return [
      for (final r in _all)
        if (r.nombre.toLowerCase().contains(q) ||
            (r.nie ?? '').toLowerCase().contains(q))
          r,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return AlertDialog(
      title: Text('facturacion.pickCliente'.tr()),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              label: 'clients.searchHint'.tr(),
              controller: _q,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              )
            else
              SizedBox(
                height: 280,
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    return ListTile(
                      title: Text(r.nombre),
                      subtitle: (r.nie ?? '').isEmpty ? null : Text(r.nie!),
                      onTap: () => Navigator.pop(context, r),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('clients.cancel'.tr()),
        ),
      ],
    );
  }
}

class _IssuedDraftDialog extends ConsumerStatefulWidget {
  const _IssuedDraftDialog({
    required this.tenantId,
    required this.serie,
    required this.numero,
  });

  final String tenantId;
  final String serie;
  final String numero;

  @override
  ConsumerState<_IssuedDraftDialog> createState() => _IssuedDraftDialogState();
}

class _IssuedDraftDialogState extends ConsumerState<_IssuedDraftDialog> {
  final _amount = TextEditingController();
  final _concept = TextEditingController();
  _PickedCliente? _cliente;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _concept.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('facturacion.addIssued'.tr()),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _cliente?.nombre ?? 'facturacion.pickCliente'.tr(),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final picked = await showDialog<_PickedCliente>(
                  context: context,
                  builder: (ctx) => const _ClientePickDialog(),
                );
                if (picked != null) setState(() => _cliente = picked);
              },
            ),
            AppTextField(
              label: 'fields.amount'.tr(),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            AppTextField(
              label: 'fields.concept'.tr(),
              controller: _concept,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text('clients.cancel'.tr()),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text('clients.save'.tr()),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final total = parseEurosToCents(_amount.text) ?? 0;
    if (total <= 0) return;
    final ivaBps = 2100;
    final base = (total * 10000 / (10000 + ivaBps)).round();
    final iva = total - base;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    setState(() => _busy = true);
    try {
      await createFacturaEmitida(
        tenantId: widget.tenantId,
        clienteId: _cliente?.id,
        destinatarioNombre: _cliente?.nombre,
        destinatarioNif: _cliente?.nie,
        serie: widget.serie,
        numero: widget.numero,
        fecha: today,
        concepto: _concept.text.trim(),
        baseCents: base,
        ivaCents: iva,
        totalCents: total,
        ivaBps: ivaBps,
        createdBy: ref.read(authControllerProvider).valueOrNull?.profile?.id,
      );
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
