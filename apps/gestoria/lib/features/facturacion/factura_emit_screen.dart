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
import '../carpeta/carpeta_controller.dart';
import '../settings/office_settings_controller.dart';
import 'factura_cliente_pick.dart';
import 'factura_lineas.dart';
import 'facturacion_providers.dart';
import 'sif_emit.dart';
import 'sif_qr.dart';

/// Celý koncept vydané — jako Holded: příjemce ze seznamu nebo ručně, řádky, DPH.
class FacturaEmitScreen extends ConsumerStatefulWidget {
  const FacturaEmitScreen({super.key});

  @override
  ConsumerState<FacturaEmitScreen> createState() => _FacturaEmitScreenState();
}

class _LineEditors {
  _LineEditors({
    String descripcion = '',
    String cantidad = '1',
    String precio = '',
    String descuento = '',
  })  : descripcion = TextEditingController(text: descripcion),
        cantidad = TextEditingController(text: cantidad),
        precio = TextEditingController(text: precio),
        descuento = TextEditingController(text: descuento);

  final TextEditingController descripcion;
  final TextEditingController cantidad;
  final TextEditingController precio;
  final TextEditingController descuento;
  int ivaBps = 2100;

  FacturaLinea toLinea() {
    return FacturaLinea(
      descripcion: descripcion.text,
      cantidad: parseQuantity(cantidad.text) ?? 0,
      precioUnitarioCents: parseEurosToCents(precio.text) ?? 0,
      ivaBps: ivaBps,
      descuentoBps: parsePercentToBps(descuento.text),
    );
  }

  void dispose() {
    descripcion.dispose();
    cantidad.dispose();
    precio.dispose();
    descuento.dispose();
  }
}

class _FacturaEmitScreenState extends ConsumerState<FacturaEmitScreen> {
  final _serie = TextEditingController();
  final _numero = TextEditingController();
  final _fecha = TextEditingController();
  final _vencimiento = TextEditingController();
  final _nombre = TextEditingController();
  final _nif = TextEditingController();
  final _email = TextEditingController();
  final _direccion = TextEditingController();
  final _concepto = TextEditingController();
  final _notas = TextEditingController();
  final _lines = <_LineEditors>[_LineEditors()];
  var _tipo = 'F1';
  var _pago = 'transferencia';
  String? _clienteId;
  String? _clienteLabel;
  var _busy = false;
  var _primed = false;

  @override
  void dispose() {
    _serie.dispose();
    _numero.dispose();
    _fecha.dispose();
    _vencimiento.dispose();
    _nombre.dispose();
    _nif.dispose();
    _email.dispose();
    _direccion.dispose();
    _concepto.dispose();
    _notas.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  FacturaTotales get _totals =>
      totalsFromLineas(_lines.map((e) => e.toLinea()));

  void _prime(OfficeSettings settings, String tenantId) {
    if (_primed) return;
    _primed = true;
    final serie = settings.facturaSerie.trim().isEmpty
        ? 'A'
        : settings.facturaSerie.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _serie.text = serie;
      _fecha.text = todayIsoDate();
      final n = await nextFacturaNumero(tenantId: tenantId, serie: serie);
      if (!mounted) return;
      if (_numero.text.isEmpty) _numero.text = '$n';
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider).valueOrNull;
    final tenantId = auth?.currentTenantId;
    final settings = ref.watch(officeSettingsProvider).valueOrNull;
    if (tenantId != null && settings != null) {
      _prime(settings, tenantId);
    }
    final totals = _totals;
    final emisorNif = (settings?.emisorNif ?? '').trim();

    return FeatureGate(
      module: GestoriaModule.facturacion,
      fallback: Scaffold(
        body: Center(child: Text('facturacion.moduleOff'.tr())),
      ),
      child: Scaffold(
        body: ListView(
          children: [
            AppContent(
              maxWidth: AppTheme.contentWide,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => context.go('/facturacion/emitidas'),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: Text('facturacion.backToList'.tr()),
                    ),
                  ),
                  AppPageHeader(
                    kicker: settings?.displayName,
                    title: 'facturacion.composeTitle'.tr(),
                    subtitle: 'facturacion.composeHint'.tr(),
                    actions: [
                      OutlinedButton(
                        onPressed: _busy ? null : () => _save(emit: false),
                        child: Text('facturacion.saveDraft'.tr()),
                      ),
                      FilledButton(
                        onPressed: _busy ? null : () => _save(emit: true),
                        child: Text('facturacion.emitir'.tr()),
                      ),
                    ],
                  ),
                  if (emisorNif.isEmpty) ...[
                    AppSectionCard(
                      title: 'facturacion.emisor'.tr(),
                      hint: 'facturacion.emisorMissing'.tr(),
                      trailing: TextButton(
                        onPressed: () => context.go('/settings/facturacion'),
                        child: Text('nav.settings'.tr()),
                      ),
                      child: const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _twoCol(
                    AppSectionCard(
                      title: 'facturacion.destinatario'.tr(),
                      hint: 'facturacion.destinatarioHint'.tr(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _pickCliente,
                                icon: const Icon(
                                  Icons.person_search_outlined,
                                  size: 18,
                                ),
                                label: Text('facturacion.pickCliente'.tr()),
                              ),
                              if (_clienteId != null)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() {
                                            _clienteId = null;
                                            _clienteLabel = null;
                                          }),
                                  child: Text('facturacion.clearCliente'.tr()),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_clienteLabel != null) ...[
                            AppInsetRow(
                              title: _clienteLabel!,
                              subtitle: _nif.text.trim().isEmpty
                                  ? null
                                  : _nif.text.trim(),
                              leading: const Icon(Icons.folder_open_outlined),
                            ),
                            const SizedBox(height: 12),
                          ],
                          AppTextField(
                            label: 'facturacion.destinatarioNombre'.tr(),
                            controller: _nombre,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          AppTextField(
                            label: 'facturacion.destinatarioNif'.tr(),
                            controller: _nif,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          AppTextField(
                            label: 'fields.email'.tr(),
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 8),
                          AppTextField(
                            label: 'fields.address'.tr(),
                            controller: _direccion,
                          ),
                        ],
                      ),
                    ),
                    AppSectionCard(
                      title: 'facturacion.invoiceData'.tr(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              AppStamp(
                                label: 'facturacion.tipoF1'.tr(),
                                selected: _tipo == 'F1',
                                onTap: () => setState(() => _tipo = 'F1'),
                              ),
                              AppStamp(
                                label: 'facturacion.tipoF2'.tr(),
                                selected: _tipo == 'F2',
                                onTap: () => setState(() => _tipo = 'F2'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _tipo == 'F2'
                                ? 'facturacion.tipoF2Hint'.tr()
                                : 'facturacion.tipoF1Hint'.tr(),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.pencil,
                                    ),
                          ),
                          const SizedBox(height: 16),
                          _twoCol(
                            AppTextField(
                              label: 'facturacion.serie'.tr(),
                              controller: _serie,
                            ),
                            AppTextField(
                              label: 'facturacion.numero'.tr(),
                              controller: _numero,
                              keyboardType: TextInputType.number,
                            ),
                            breakpoint: 520,
                          ),
                          const SizedBox(height: 8),
                          _twoCol(
                            AppTextField(
                              label: 'fields.issued'.tr(),
                              controller: _fecha,
                            ),
                            AppTextField(
                              label: 'fields.due'.tr(),
                              controller: _vencimiento,
                            ),
                            breakpoint: 520,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'facturacion.formaPago'.tr(),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final key in const [
                                'transferencia',
                                'efectivo',
                                'tarjeta',
                                'domiciliacion',
                                'otro',
                              ])
                                AppStamp(
                                  label: 'facturacion.pago.$key'.tr(),
                                  selected: _pago == key,
                                  onTap: () => setState(() => _pago = key),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppSectionCard(
                    title: 'facturacion.lineas'.tr(),
                    hint: 'facturacion.lineasHint'.tr(),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'facturacion.descripcion'.tr(),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ),
                        for (var i = 0; i < _lines.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          _LineCard(
                            index: i,
                            line: _lines[i],
                            canRemove: _lines.length > 1,
                            onChanged: () => setState(() {}),
                            onRemove: () => setState(() {
                              final gone = _lines.removeAt(i);
                              gone.dispose();
                            }),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _lines.add(_LineEditors())),
                            icon: const Icon(Icons.add, size: 18),
                            label: Text('facturacion.addLine'.tr()),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _twoCol(
                    AppSectionCard(
                      title: 'fields.concept'.tr(),
                      hint: 'facturacion.conceptoHint'.tr(),
                      child: Column(
                        children: [
                          AppTextField(
                            label: 'fields.concept'.tr(),
                            controller: _concepto,
                            minLines: 2,
                            maxLines: 3,
                            alignLabelWithHint: true,
                          ),
                          const SizedBox(height: 8),
                          AppTextField(
                            label: 'facturacion.notas'.tr(),
                            controller: _notas,
                            minLines: 2,
                            maxLines: 4,
                            alignLabelWithHint: true,
                          ),
                        ],
                      ),
                    ),
                    AppSectionCard(
                      title: 'facturacion.totals'.tr(),
                      child: Column(
                        children: [
                          for (final row in totals.byRate) ...[
                            _TotalRow(
                              label:
                                  '${'fields.base'.tr()} ${ivaRateLabel(row.ivaBps)}',
                              value: '${formatCents(row.baseCents)} €',
                            ),
                            _TotalRow(
                              label:
                                  '${'fields.iva'.tr()} ${ivaRateLabel(row.ivaBps)}',
                              value: '${formatCents(row.ivaCents)} €',
                            ),
                          ],
                          if (totals.byRate.isEmpty)
                            _TotalRow(
                              label: 'fields.base'.tr(),
                              value: '0,00 €',
                            ),
                          const SizedBox(height: 8),
                          const Divider(),
                          const SizedBox(height: 8),
                          _TotalRow(
                            label: 'facturacion.grandTotal'.tr(),
                            value: '${formatCents(totals.totalCents)} €',
                            emphasize: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _twoCol(Widget left, Widget right, {double breakpoint = 760}) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              left,
              const SizedBox(height: 16),
              right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 16),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  Future<void> _pickCliente() async {
    final picked = await showDialog<FacturaClientePick>(
      context: context,
      builder: (ctx) => const FacturaClientePickDialog(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _clienteId = picked.id;
      _clienteLabel = picked.nombre;
      _nombre.text = picked.nombre;
      if ((picked.nie ?? '').isNotEmpty) _nif.text = picked.nie!;
      if ((picked.email ?? '').isNotEmpty) _email.text = picked.email!;
      if ((picked.direccion ?? '').isNotEmpty) {
        _direccion.text = picked.direccion!;
      }
    });
  }

  Future<void> _save({required bool emit}) async {
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    if (tenantId == null) return;
    final totals = _totals;
    final fecha = toIsoDate(_fecha.text);
    final numero = _numero.text.trim();
    final serie = _serie.text.trim().isEmpty ? 'A' : _serie.text.trim();
    if (numero.isEmpty || fecha == null) {
      _snack('facturacion.numeroFechaRequired');
      return;
    }
    if (totals.isEmpty) {
      _snack('facturacion.linesRequired');
      return;
    }
    if (_tipo == 'F1' &&
        (_nombre.text.trim().isEmpty || _nif.text.trim().isEmpty)) {
      _snack('facturacion.destinatarioRequired');
      return;
    }
    if (_tipo == 'F2' && totals.exceedsF2Limit) {
      _snack('facturacion.f2OverLimit');
      return;
    }
    final concepto = _concepto.text.trim().isNotEmpty
        ? _concepto.text.trim()
        : (totals.lineas.isNotEmpty
            ? totals.lineas.first.descripcion
            : 'Servicios');
    setState(() => _busy = true);
    try {
      final id = await createFacturaEmitida(
        tenantId: tenantId,
        clienteId: _clienteId,
        destinatarioNombre: _opt(_nombre.text),
        destinatarioNif: _opt(_nif.text)?.toUpperCase(),
        destinatarioDireccion: _opt(_direccion.text),
        destinatarioEmail: _opt(_email.text),
        serie: serie,
        numero: numero,
        fecha: fecha,
        vencimiento: toIsoDate(_vencimiento.text),
        concepto: concepto,
        notas: _opt(_notas.text),
        formaPago: _pago,
        tipoFactura: _tipo,
        lineas: [for (final l in totals.lineas) l.toJson()],
        baseCents: totals.baseCents,
        ivaCents: totals.ivaCents,
        totalCents: totals.totalCents,
        ivaBps: totals.dominantIvaBps ?? 2100,
        createdBy: ref.read(authControllerProvider).valueOrNull?.profile?.id,
      );
      if (!mounted) return;
      ref.invalidate(facturasOfficeProvider);
      ref.invalidate(facturasClienteProvider);
      ref.invalidate(carpetaControllerProvider);
      if (!emit) {
        context.go('/facturacion/emitidas');
        return;
      }
      final result = await emitFacturaViaSif(
        tenantId: tenantId,
        facturaId: id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sifSnackKey(result, verify: false).tr())),
      );
      ref.invalidate(facturasOfficeProvider);
      ref.invalidate(facturasClienteProvider);
      ref.invalidate(carpetaControllerProvider);
      if (result.ok) {
        await showSifQrDialog(
          context,
          qrStored: result.sifQrUrl,
          aeatUrl: result.sifAeatUrl,
        );
      }
      if (mounted) context.go('/facturacion/emitidas');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String key) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(key.tr())),
    );
  }

  String? _opt(String raw) {
    final s = raw.trim();
    return s.isEmpty ? null : s;
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.index,
    required this.line,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _LineEditors line;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final computed = line.toLinea();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '${index + 1}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              Text(
                '${formatCents(computed.totalCents)} €',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (canRemove)
                SoftRemoveIconButton(
                  tooltip: 'clients.softDelete'.tr(),
                  onPressed: onRemove,
                ),
            ],
          ),
          const SizedBox(height: 8),
          AppTextField(
            label: 'facturacion.descripcion'.tr(),
            controller: line.descripcion,
            onChanged: (_) => onChanged(),
            minLines: 1,
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, c) {
              final stacked = c.maxWidth < 640;
              final qty = AppTextField(
                label: 'facturacion.cantidad'.tr(),
                controller: line.cantidad,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => onChanged(),
              );
              final precio = AppTextField(
                label: 'facturacion.precio'.tr(),
                controller: line.precio,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => onChanged(),
              );
              final dto = AppTextField(
                label: 'facturacion.descuento'.tr(),
                controller: line.descuento,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => onChanged(),
              );
              final iva = DropdownButtonFormField<int>(
                initialValue: line.ivaBps,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'fields.ivaRate'.tr(),
                ),
                items: [
                  for (final bps in kIvaRatesBps)
                    DropdownMenuItem(
                      value: bps,
                      child: Text(ivaRateLabel(bps)),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  line.ivaBps = v;
                  onChanged();
                },
              );
              if (stacked) {
                return Column(
                  children: [
                    qty,
                    const SizedBox(height: 8),
                    precio,
                    const SizedBox(height: 8),
                    dto,
                    const SizedBox(height: 8),
                    iva,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: qty),
                  const SizedBox(width: 8),
                  Expanded(flex: 3, child: precio),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: dto),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: iva),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
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
          Text(value, style: style),
        ],
      ),
    );
  }
}
