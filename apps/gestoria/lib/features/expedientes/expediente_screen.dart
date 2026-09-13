import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/staff_role.dart';
import '../../core/documents/office_attach_button.dart';
import '../../core/documents/office_file_pick.dart';
import '../../core/money/cents.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../carpeta/bloque_template.dart';
import '../carpeta/carpeta_controller.dart';
import '../carpeta/carpeta_routes.dart';
import '../clientes/cliente_audit.dart';
import '../inbox/inbox_providers.dart';
import 'expediente_controller.dart';
import 'expediente_estado.dart';
import 'modelo_210.dart';

class ExpedienteScreen extends ConsumerStatefulWidget {
  const ExpedienteScreen({super.key, required this.expedienteId});

  final String expedienteId;

  @override
  ConsumerState<ExpedienteScreen> createState() => _ExpedienteScreenState();
}

class _ExpedienteScreenState extends ConsumerState<ExpedienteScreen> {
  final _controllers = <String, TextEditingController>{};
  var _busy = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(String key, String value) {
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: value),
    );
  }

  /// Po navázání nemovitosti doplníme prázdná pole, aniž by se přepsala tužka.
  void _syncFields(ThinExpedienteView view) {
    for (final key in view.kind.fieldKeys) {
      final raw = view.bloque.values[key] ?? '';
      final next = _displayValue(key, raw);
      final c = _ctrl(key, next);
      if (c.text != next) c.text = next;
    }
  }

  String _displayValue(String key, String raw) {
    if (!modelo210MoneyKeys.contains(key)) return raw;
    if (raw.trim().isEmpty) return '';
    return formatCents(centsFromStored(raw));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(thinExpedienteProvider(widget.expedienteId));
    return async.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text('expedientes.title'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        appBar: AppBar(
          title: Text('expedientes.title'.tr()),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/clientes'),
          ),
        ),
        body: Center(child: Text('expedientes.loadError'.tr())),
      ),
      data: (view) {
        _syncFields(view);
        final ctrl =
            ref.read(thinExpedienteProvider(widget.expedienteId).notifier);
        final auth = ref.watch(authControllerProvider).valueOrNull;
        final canDelete = auth != null && canSoftDeleteExpediente(auth);
        final tax = view.kind.tipo == 'impuestos_210' ||
            view.kind.tipo == 'impuestos_renta';
        return Scaffold(
          appBar: AppBar(
            title: Text('expedientes.tipo.${view.kind.tipo}'.tr()),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/clientes/${view.clienteId}'),
            ),
          ),
          body: AppContent(
            child: ListView(
              children: [
                AppPageHeader(
                  kicker: view.clienteNie,
                  title: view.clienteNombre.isEmpty
                      ? 'expedientes.tipo.${view.kind.tipo}'.tr()
                      : view.clienteNombre,
                  subtitle: view.kind.tipo == 'impuestos_210'
                      ? 'expedientes.intro210'.tr()
                      : tax
                          ? 'expedientes.intro'.tr()
                          : 'expedientes.introTramite'.tr(),
                  actions: [
                    OutlinedButton(
                      onPressed: () =>
                          context.go('/clientes/${view.clienteId}'),
                      child: Text('expedientes.openCard'.tr()),
                    ),
                    if (view.compraventaExpedienteId != null)
                      FilledButton.tonal(
                        onPressed: () => context.go(
                          carpetaRoute(
                            view.clienteId,
                            expedienteId: view.compraventaExpedienteId,
                          ),
                        ),
                        child: Text('expedientes.openFolder'.tr()),
                      ),
                  ],
                ),
                AppSectionCard(
                  title: 'expedientes.desk'.tr(),
                  trailing: Builder(
                    builder: (context) {
                      final s = bloqueUiStatus(view.bloque.dbStatus);
                      return Chip(
                        label: Text(
                          statusLabel(s),
                          style: TextStyle(
                            color: bloqueStatusInk(s),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        backgroundColor: bloqueStatusFill(s),
                      );
                    },
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ExpedienteEstadoPicker(
                        estado: view.estado,
                        onChanged: (v) async {
                          await setExpedienteEstado(
                            expedienteId: view.id,
                            estado: v,
                          );
                          ref.invalidate(
                            thinExpedienteProvider(widget.expedienteId),
                          );
                          ref.invalidate(inboxFeedProvider);
                        },
                      ),
                      if (view.kind.linksInmueble) ...[
                        const SizedBox(height: 16),
                        DropdownMenu<String>(
                          key: ValueKey('inm-${view.inmuebleId ?? ''}'),
                          initialSelection: view.inmuebleId ?? '',
                          label: Text('expedientes.property'.tr()),
                          expandedInsets: EdgeInsets.zero,
                          dropdownMenuEntries: [
                            DropdownMenuEntry(
                              value: '',
                              label: 'expedientes.noProperty'.tr(),
                            ),
                            for (final inm in view.inmuebles)
                              DropdownMenuEntry(
                                value: inm.id,
                                label: inm.catastral == null
                                    ? inm.direccion
                                    : '${inm.direccion} · ${inm.catastral}',
                              ),
                          ],
                          onSelected: (v) {
                            if (v == null) return;
                            ctrl.setInmueble(v.isEmpty ? null : v);
                          },
                        ),
                        if (view.inmuebles.isEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'expedientes.noInmuebleHint'.tr(),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.pencil),
                          ),
                        ],
                      ],
                      const SizedBox(height: 16),
                      for (final key in view.kind.fieldKeys)
                        if (!modelo210TaxInputKeys.contains(key) &&
                            !modelo210OutputKeys.contains(key)) ...[
                          _field(view, key, ctrl),
                          const SizedBox(height: 12),
                        ],
                      if (view.kind.tipo == 'impuestos_210') ...[
                        const SizedBox(height: 8),
                        _taxBlock(view, ctrl),
                        const SizedBox(height: 16),
                      ],
                      FilledButton(
                        onPressed: _busy ? null : _save,
                        child: Text('clients.save'.tr()),
                      ),
                    ],
                  ),
                ),
                if (view.kind.paperSlotTypes.isNotEmpty ||
                    view.bloque.documents.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  AppSectionCard(
                    title: 'expedientes.papers'.tr(),
                    hint: view.kind.requiredDocsMode == RequiredDocsMode.any
                        ? 'folder.requiredDocsAny'.tr(
                            namedArgs: {
                              'types': view.kind.requiredDocTypes
                                  .map((t) => 'docs.$t'.tr())
                                  .join(', '),
                            },
                          )
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0;
                            i < view.kind.paperSlotTypes.length;
                            i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          _PaperSlot(
                            tipo: view.kind.paperSlotTypes[i],
                            requiredSlot: view.kind.requiredDocTypes
                                .contains(view.kind.paperSlotTypes[i]),
                            docs: view.bloque.documents
                                .where(
                                  (d) =>
                                      d.tipo == view.kind.paperSlotTypes[i],
                                )
                                .toList(),
                            busy: _busy,
                            onAttach: (file) => _attachPicked(
                              file,
                              tipo: view.kind.paperSlotTypes[i],
                            ),
                            onOpen: _openDoc,
                            onRemove: _removeDoc,
                          ),
                        ],
                        ..._otherPapers(view),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (canDelete)
                  TextButton(
                    onPressed: _busy ? null : () => _softDelete(view.clienteId),
                    child: Text('expedientes.softDelete'.tr()),
                  )
                else
                  Text('expedientes.asistenteNoDelete'.tr()),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _otherPapers(ThinExpedienteView view) {
    final known = view.kind.paperSlotTypes.toSet();
    final extra = [
      for (final d in view.bloque.documents)
        if (!known.contains(d.tipo)) d,
    ];
    if (extra.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      Text(
        'expedientes.otherPapers'.tr(),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      for (final doc in extra)
        _PaperFileRow(
          doc: doc,
          busy: _busy,
          onOpen: _openDoc,
          onRemove: _removeDoc,
        ),
    ];
  }

  Widget _taxBlock(ThinExpedienteView view, ThinExpedienteController ctrl) {
    final result = computeModelo210FromFields(view.bloque.values);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('tax.title'.tr(), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'tax.hint'.tr(),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppTheme.pencil),
        ),
        const SizedBox(height: 12),
        for (final key in modelo210VisibleInputs(view.bloque.values)) ...[
          _field(view, key, ctrl),
          const SizedBox(height: 12),
        ],
        if (result.ok)
          AppCard(
            emphasized: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'tax.aeatTipo'.tr(
                      namedArgs: {'code': result.aeatTipo},
                    ),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'tax.base'.tr(
                      namedArgs: {'amount': formatCents(result.taxBaseCents)},
                    ),
                  ),
                  Text(
                    'tax.rate'.tr(
                      namedArgs: {'rate': '${result.ratePercent}'},
                    ),
                  ),
                  Text(
                    'tax.cuota'.tr(
                      namedArgs: {'amount': formatCents(result.cuotaCents)},
                    ),
                  ),
                  if (result.withholdingCents != 0)
                    Text(
                      'tax.withholding'.tr(
                        namedArgs: {
                          'amount': formatCents(result.withholdingCents),
                        },
                      ),
                    ),
                  Text(
                    result.taxDueCents < 0
                        ? 'tax.refund'.tr(
                            namedArgs: {
                              'amount': formatCents(-result.taxDueCents),
                            },
                          )
                        : 'tax.due'.tr(
                            namedArgs: {
                              'amount': formatCents(result.taxDueCents),
                            },
                          ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'tax.formula'.tr(
                      namedArgs: {'id': result.formula},
                    ),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.pencil),
                  ),
                ],
              ),
            ),
          )
        else if (result.missingKeys.isNotEmpty)
          Text(
            'tax.missing'.tr(
              namedArgs: {
                'fields': result.missingKeys.map((k) => k.tr()).join(', '),
              },
            ),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.statusWarn),
          ),
        for (final note in result.notes) ...[
          const SizedBox(height: 8),
          Text(
            note.tr(),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.pencil),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'tax.disclaimer'.tr(),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppTheme.pencil),
        ),
      ],
    );
  }

  Widget _field(
    ThinExpedienteView view,
    String key,
    ThinExpedienteController ctrl,
  ) {
    final value = view.bloque.values[key] ?? '';
    if (key == 'fields.periodicity') {
      return _drop(key, value, const {
        'trimestral': 'expedientes.periodicidad.trimestral',
        'anual': 'expedientes.periodicidad.anual',
      }, ctrl);
    }
    if (key == 'fields.nieStatus' || key == 'fields.tramiteStatus') {
      return _drop(key, value, const {
        'cita': 'expedientes.nieStatus.cita',
        'presentado': 'expedientes.nieStatus.presentado',
        'resuelto': 'expedientes.nieStatus.resuelto',
        'rechazado': 'expedientes.nieStatus.rechazado',
      }, ctrl);
    }
    if (key == 'fields.incomeKind') {
      return _drop(key, value, const {
        'imputacion': 'tax.kind.imputacion',
        'alquiler': 'tax.kind.alquiler',
        'transmision': 'tax.kind.transmision',
      }, ctrl);
    }
    if (key == 'fields.taxResidency') {
      return _drop(key, value, const {
        'ue': 'tax.residency.ue',
        'other': 'tax.residency.other',
      }, ctrl);
    }
    if (key == 'fields.imputeRate') {
      return _drop(key, value, const {
        '11': 'tax.impute.11',
        '20': 'tax.impute.20',
        'no_cadastral': 'tax.impute.none',
      }, ctrl);
    }
    if (key == 'fields.multiPayer' || key == 'fields.bought2012') {
      return _drop(key, value, const {
        'yes': 'tax.yes',
        'no': 'tax.no',
      }, ctrl);
    }
    final notes = key == 'fields.notes';
    final money = modelo210MoneyKeys.contains(key);
    final shown = _displayValue(key, value);
    return AppTextField(
      label: key.tr(),
      controller: _ctrl(key, shown),
      keyboardType: money
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      onChanged: (v) {
        if (money) {
          final cents = parseEurosToCents(v);
          ctrl.setField(key, cents == null ? '' : '$cents');
          return;
        }
        ctrl.setField(key, v);
      },
      minLines: notes ? 3 : null,
      maxLines: notes ? 6 : 1,
    );
  }

  Widget _drop(
    String key,
    String value,
    Map<String, String> entries,
    ThinExpedienteController ctrl,
  ) {
    return DropdownMenu<String>(
      key: ValueKey('$key-$value'),
      initialSelection: value.isEmpty ? null : value,
      label: Text(key.tr()),
      expandedInsets: EdgeInsets.zero,
      dropdownMenuEntries: [
        for (final e in entries.entries)
          DropdownMenuEntry(value: e.key, label: e.value.tr()),
      ],
      onSelected: (v) {
        if (v == null) return;
        ctrl.setField(key, v);
      },
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(thinExpedienteProvider(widget.expedienteId).notifier)
          .save();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('clients.saved'.tr())),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('clients.saveError'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attachPicked(PickedOfficeFile file, {String? tipo}) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(thinExpedienteProvider(widget.expedienteId).notifier)
          .attachDocument(
            bytes: file.bytes,
            originalName: file.name,
            tipo: tipo,
          );
    } on Object catch (e) {
      if (mounted) showOfficeUploadFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDoc(CarpetaDocumento doc) async {
    try {
      final url = await ref
          .read(thinExpedienteProvider(widget.expedienteId).notifier)
          .signedUrl(doc.storagePath);
      if (url == null) throw StateError('url');
      final view =
          ref.read(thinExpedienteProvider(widget.expedienteId)).valueOrNull;
      if (view != null) {
        await auditDocumentoOpen(
          documentId: doc.id,
          tenantId: view.tenantId,
          tipo: doc.tipo,
          originalName: doc.originalName,
        );
      }
      await launchUrl(Uri.parse(url));
    } on Object {
      if (mounted) _toast('folder.openError'.tr());
    }
  }

  Future<void> _removeDoc(String documentId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('folder.remove'.tr()),
        content: Text('folder.removeConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('clients.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('folder.remove'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(thinExpedienteProvider(widget.expedienteId).notifier)
          .removeDocument(documentId);
    } on Object {
      if (mounted) _toast('folder.removeError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _softDelete(String clienteId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('expedientes.softDelete'.tr()),
        content: Text('expedientes.softDeleteConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('clients.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('expedientes.softDelete'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(thinExpedienteProvider(widget.expedienteId).notifier)
          .softDelete();
      if (mounted) context.go('/clientes/$clienteId');
    } on Object {
      if (mounted) _toast('clients.saveError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _PaperSlot extends StatelessWidget {
  const _PaperSlot({
    required this.tipo,
    required this.requiredSlot,
    required this.docs,
    required this.busy,
    required this.onAttach,
    required this.onOpen,
    required this.onRemove,
  });

  final String tipo;
  final bool requiredSlot;
  final List<CarpetaDocumento> docs;
  final bool busy;
  final void Function(PickedOfficeFile file) onAttach;
  final void Function(CarpetaDocumento doc) onOpen;
  final void Function(String id) onRemove;

  @override
  Widget build(BuildContext context) {
    final missing = docs.isEmpty;
    return AppCard(
      stripe: missing
          ? (requiredSlot ? AppTheme.statusWarn : AppTheme.statusWatch)
          : AppTheme.statusOk,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'docs.$tipo'.tr(),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  missing
                      ? (requiredSlot
                          ? 'expedientes.paperMissing'.tr()
                          : 'expedientes.optionalPaper'.tr())
                      : 'expedientes.paperInFolder'.tr(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.pencil,
                      ),
                ),
              ],
            ),
            for (final doc in docs)
              _PaperFileRow(
                doc: doc,
                busy: busy,
                onOpen: onOpen,
                onRemove: onRemove,
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: OfficeAttachButton(
                enabled: !busy,
                outlined: missing,
                label: 'folder.attach'.tr(),
                onPicked: onAttach,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaperFileRow extends StatelessWidget {
  const _PaperFileRow({
    required this.doc,
    required this.busy,
    required this.onOpen,
    required this.onRemove,
  });

  final CarpetaDocumento doc;
  final bool busy;
  final void Function(CarpetaDocumento doc) onOpen;
  final void Function(String id) onRemove;

  @override
  Widget build(BuildContext context) {
    return AppInsetRow(
      leading: const Icon(Icons.insert_drive_file_outlined, size: 20),
      title: doc.originalName.isEmpty
          ? 'docs.${doc.tipo}'.tr()
          : doc.originalName,
      subtitle: 'docs.${doc.tipo}'.tr(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'folder.open'.tr(),
            icon: const Icon(Icons.open_in_new),
            onPressed: () => onOpen(doc),
          ),
          IconButton(
            tooltip: 'folder.remove'.tr(),
            icon: const Icon(Icons.delete_outline),
            onPressed: busy ? null : () => onRemove(doc.id),
          ),
        ],
      ),
    );
  }
}
