import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/modules/slot_order.dart';
import '../../core/money/cents.dart';
import '../../core/money/provision.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../ai/ai_providers.dart';
import '../ai/documento_fields.dart';
import '../ai/extract_text.dart';
import '../expedientes/expediente_controller.dart';
import '../expedientes/expediente_estado.dart';
import '../inbox/inbox_providers.dart';
import '../settings/office_settings_controller.dart';
import 'bloque_template.dart';
import 'carpeta_controller.dart';

class CarpetaScreen extends ConsumerWidget {
  const CarpetaScreen({
    super.key,
    required this.clienteId,
    this.expedienteId,
  });

  final String clienteId;
  final String? expedienteId;

  CarpetaTarget get _target =>
      CarpetaTarget(clienteId: clienteId, expedienteId: expedienteId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(carpetaControllerProvider(_target));
    return async.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text('folder.title'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        appBar: AppBar(
          title: Text('folder.title'.tr()),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/clientes'),
          ),
        ),
        body: Center(child: Text('folder.loadError'.tr())),
      ),
      data: (view) {
        final modules = ref.watch(tenantConfigProvider).valueOrNull;
        final order = slotKeys(
          ref.watch(officeSettingsProvider).valueOrNull?.slotOrder,
          carpetaBlocksSlot,
        );
        final templates = applySlotOrder(
          items: compraventaBloques.where((t) {
            if (t.moduleKey == 'carpeta_inmueble') return true;
            final m = GestoriaModuleKey.fromKey(t.moduleKey);
            return m == null || (modules?.isOn(m) ?? false);
          }).toList(),
          order: order,
          keyOf: (t) => t.key,
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(
              view.nombre.isEmpty ? 'folder.title'.tr() : view.nombre,
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/clientes/$clienteId'),
            ),
            actions: [
              FeatureGate(
                module: GestoriaModule.messaging,
                child: IconButton(
                  tooltip: 'messages.title'.tr(),
                  icon: const Icon(Icons.mail_outline),
                  onPressed: () =>
                      context.go('/clientes/$clienteId/mensaje'),
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(28),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  view.inmuebleDireccion == null ||
                          view.inmuebleDireccion!.isEmpty
                      ? 'folder.subtitle'.tr()
                      : view.inmuebleDireccion!,
                  style: const TextStyle(color: AppTheme.pencil, fontSize: 13),
                ),
              ),
            ),
          ),
          body: FeatureGate(
            module: GestoriaModule.carpetaInmueble,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1100;
                final enabled = templates
                    .where(
                      (t) =>
                          (view.bloques[t.key] ?? const BloqueState(enabled: false))
                              .enabled,
                    )
                    .toList();
                final disabled = templates
                    .where(
                      (t) =>
                          !(view.bloques[t.key] ?? const BloqueState(enabled: false))
                              .enabled,
                    )
                    .toList();
                Widget cardFor(BloqueTemplate template, {required bool compact}) {
                  final state = view.bloques[template.key] ??
                      const BloqueState(enabled: false);
                  return _BloqueCard(
                    key: ValueKey(template.key),
                    target: _target,
                    template: template,
                    state: state,
                    movements: view.movements,
                    clienteNombre: view.nombre,
                    compact: compact,
                  );
                }

                Widget enabledGrid() {
                  if (enabled.isEmpty) return const SizedBox.shrink();
                  if (!wide) {
                    return Column(
                      children: [for (final t in enabled) cardFor(t, compact: false)],
                    );
                  }
                  final left = [for (var i = 0; i < enabled.length; i += 2) enabled[i]];
                  final right = [for (var i = 1; i < enabled.length; i += 2) enabled[i]];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            for (final t in left) cardFor(t, compact: false),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: [
                            for (final t in right) cardFor(t, compact: false),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppTheme.contentWide,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (view.expedienteId != null)
                              ExpedienteEstadoPicker(
                                estado: view.expedienteEstado,
                                onChanged: (v) async {
                                  await setExpedienteEstado(
                                    expedienteId: view.expedienteId!,
                                    estado: v,
                                  );
                                  ref.invalidate(
                                    carpetaControllerProvider(_target),
                                  );
                                  ref.invalidate(inboxFeedProvider);
                                },
                              ),
                            if (view.expedienteId != null)
                              const SizedBox(height: 16),
                            enabledGrid(),
                            if (disabled.isNotEmpty) ...[
                              const SizedBox(height: 24),
                              Text(
                                'folder.offBlocks'.tr(),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'folder.offBlocksHint'.tr(),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 12),
                              for (final t in disabled)
                                cardFor(t, compact: true),
                            ],
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
      },
    );
  }
}

class _BloqueCard extends ConsumerStatefulWidget {
  const _BloqueCard({
    super.key,
    required this.target,
    required this.template,
    required this.state,
    this.movements = const [],
    this.clienteNombre = '',
    this.compact = false,
  });

  final CarpetaTarget target;
  final BloqueTemplate template;
  final BloqueState state;
  final List<ProvisionMovement> movements;
  final String clienteNombre;
  final bool compact;

  @override
  ConsumerState<_BloqueCard> createState() => _BloqueCardState();
}

class _BloqueCardState extends ConsumerState<_BloqueCard> {
  late final Map<String, TextEditingController> _fields;

  @override
  void initState() {
    super.initState();
    _fields = {
      for (final f in widget.template.fieldKeys)
        if (f != 'fields.remaining')
          f: TextEditingController(text: _displayField(f)),
    };
  }

  @override
  void didUpdateWidget(covariant _BloqueCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final e in widget.state.values.entries) {
      final c = _fields[e.key];
      if (c != null && c.text != e.value) c.text = e.value;
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final template = widget.template;
    final state = widget.state;
    final status = bloqueUiStatus(state.dbStatus);
    final ctrl = ref.read(carpetaControllerProvider(widget.target).notifier);
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      emphasized: state.enabled,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    template.labelI18n.tr(),
                    style: const TextStyle(
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                Flexible(
                  child: Chip(
                    label: Text(
                      statusLabel(status),
                      style: const TextStyle(fontSize: 12),
                    ),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: status == BloqueUiStatus.off
                        ? AppTheme.chipOff
                        : AppTheme.chipOn,
                  ),
                ),
                Switch(
                  value: state.enabled,
                  onChanged: (v) => _toggle(ctrl, template.key, v),
                ),
              ],
            ),
            _AiPrefillBar(
              target: widget.target,
              templateKey: template.key,
              fields: _fields,
            ),
            if (!widget.compact && state.enabled) ...[
              const SizedBox(height: 8),
              if (template.key == 'provision_factura')
                _provisionBody(context, ctrl)
              else
                for (final field in template.fieldKeys)
                  if (field == 'fields.remaining')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${field.tr()}: ${formatCents(_remainingCents(state))}',
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppTextField(
                        controller: _fields[field],
                        label: field.tr(),
                        onChanged: (v) => _onField(ctrl, template.key, field, v),
                      ),
                    ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _pickAndAttach(context, ctrl, template.key),
                  icon: const Icon(Icons.attach_file, size: 18),
                  label: Text('folder.attach'.tr()),
                ),
              ),
              if (template.requiredDocTypes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'folder.requiredDocs'.tr(
                      namedArgs: {
                        'types': template.requiredDocTypes
                            .map((t) => 'docs.$t'.tr())
                            .join(', '),
                      },
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final doc in state.documents)
                _DocumentoForm(
                  target: widget.target,
                  templateKey: template.key,
                  doc: doc,
                  clienteNombre: widget.clienteNombre,
                  onOpen: () => _openDoc(context, ctrl, doc.storagePath),
                  onRemove: () => _removeDoc(
                    context,
                    ctrl,
                    template.key,
                    doc.id,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndAttach(
    BuildContext context,
    CarpetaController ctrl,
    String templateKey,
  ) async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('folder.uploadError'.tr())),
        );
      }
      return;
    }
    try {
      final attached = await ctrl.attachDocument(
        templateKey: templateKey,
        bytes: bytes,
        originalName: file.name,
      );
      if (attached == null) return;
      final tenantId = ctrl.state.valueOrNull?.tenantId;
      final clienteId = ctrl.state.valueOrNull?.clienteId;
      if (tenantId == null || clienteId == null) return;
      final mime = switch (file.extension?.toLowerCase()) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        _ => 'image/jpeg',
      };
      final draft = await extractDocumentDraft(
        tenantId: tenantId,
        clienteId: clienteId,
        storagePath: attached.storagePath,
        mime: mime,
        docTipo: attached.tipo,
        bloqueKey: templateKey,
      );
      if (draft != null) {
        ref.read(aiPrefillProvider.notifier).state = draft;
        ref.invalidate(liveAiDraftsProvider(clienteId));
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('folder.uploadError'.tr())),
        );
      }
    }
  }

  Future<void> _openDoc(
    BuildContext context,
    CarpetaController ctrl,
    String path,
  ) async {
    try {
      final url = await ctrl.signedUrl(path);
      if (url == null) throw StateError('url');
      await launchUrl(Uri.parse(url));
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('folder.openError'.tr())),
        );
      }
    }
  }

  Future<void> _removeDoc(
    BuildContext context,
    CarpetaController ctrl,
    String templateKey,
    String documentId,
  ) async {
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
    try {
      await ctrl.removeDocument(templateKey, documentId);
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('folder.removeError'.tr())),
        );
      }
    }
  }

  String _displayField(String field) {
    final raw = widget.state.values[field] ?? '';
    if (field == 'fields.received' || field == 'fields.invoiced') {
      if (raw.trim().isEmpty) return '';
      return formatCents(centsFromStored(raw));
    }
    return raw;
  }

  Future<void> _toggle(CarpetaController ctrl, String key, bool on) async {
    if (on) {
      await ctrl.setEnabled(key, true);
      return;
    }
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('folder.offReason'.tr()),
        content: TextField(
          controller: reasonCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'folder.offReasonHint'.tr(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('clients.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('folder.offConfirm'.tr()),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (ok != true || reason.isEmpty || !mounted) return;
    await ctrl.setEnabled(key, false, reason: reason);
  }

  void _onField(
    CarpetaController ctrl,
    String key,
    String field,
    String value,
  ) {
    if (field == 'fields.received' || field == 'fields.invoiced') {
      final cents = parseEurosToCents(value);
      ctrl.setField(key, field, cents == null ? '' : '$cents');
      return;
    }
    ctrl.setField(key, field, value);
  }

  int _remainingCents(BloqueState state) {
    return centsFromStored(state.values['fields.received']) -
        centsFromStored(state.values['fields.invoiced']);
  }

  Widget _provisionBody(BuildContext context, CarpetaController ctrl) {
    final rows = widget.movements;
    final received = provisionReceivedCents(rows);
    final invoiced = provisionInvoicedCents(rows);
    final remaining = provisionRemainingCents(rows);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${'fields.received'.tr()}: ${formatCents(received)}'),
        Text('${'fields.invoiced'.tr()}: ${formatCents(invoiced)}'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('${'fields.remaining'.tr()}: ${formatCents(remaining)}'),
        ),
        Text('provision.hint'.tr()),
        const SizedBox(height: 8),
        for (final row in rows)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('provision.kind.${row.kind}'.tr()),
            subtitle: Text(
              [
                formatCents(row.amountCents),
                if (row.note != null && row.note!.isNotEmpty) row.note!,
              ].join(' · '),
            ),
            trailing: IconButton(
              tooltip: 'folder.remove'.tr(),
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => ctrl.removeProvisionMovement(row.id),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _addMovement(context, ctrl),
            icon: const Icon(Icons.add, size: 18),
            label: Text('provision.add'.tr()),
          ),
        ),
      ],
    );
  }

  Future<void> _addMovement(
    BuildContext context,
    CarpetaController ctrl,
  ) async {
    var kind = 'ingreso';
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('provision.add'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownMenu<String>(
              initialSelection: kind,
              label: Text('provision.kindLabel'.tr()),
              expandedInsets: EdgeInsets.zero,
              dropdownMenuEntries: [
                for (final k in provisionKinds)
                  DropdownMenuEntry(
                    value: k,
                    label: 'provision.kind.$k'.tr(),
                  ),
              ],
              onSelected: (v) {
                if (v != null) kind = v;
              },
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: amount,
              label: 'provision.amount'.tr(),
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: note,
              label: 'provision.note'.tr(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('clients.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('provision.add'.tr()),
          ),
        ],
      ),
    );
    final cents = parseEurosToCents(amount.text);
    final noteText = note.text;
    amount.dispose();
    note.dispose();
    if (ok != true || cents == null || cents == 0) return;
    await ctrl.addProvisionMovement(
      kind: kind,
      amountCents: cents,
      note: noteText,
    );
  }
}

class _AiPrefillBar extends ConsumerWidget {
  const _AiPrefillBar({
    required this.target,
    required this.templateKey,
    required this.fields,
  });

  final CarpetaTarget target;
  final String templateKey;
  final Map<String, TextEditingController> fields;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clienteId = target.clienteId;
    final memory = ref.watch(aiPrefillProvider);
    final live =
        ref.watch(liveAiDraftsProvider(clienteId)).valueOrNull ?? const [];
    AiPrefillDraft? draft;
    if (memory != null &&
        memory.clienteId == clienteId &&
        memory.bloqueKey == templateKey &&
        (memory.storagePath == null || memory.storagePath!.isEmpty)) {
      draft = memory;
    } else {
      for (final d in live) {
        if (d.clienteId == clienteId &&
            d.bloqueKey == templateKey &&
            (d.storagePath == null || d.storagePath!.isEmpty)) {
          draft = d;
          break;
        }
      }
    }
    if (draft == null ||
        draft.clienteId != clienteId ||
        draft.bloqueKey != templateKey) {
      return const SizedBox.shrink();
    }
    final proposal = draft;
    final current = {
      for (final e in fields.entries) e.key: e.value.text,
    };
    final diffs = prefillDiffs(current: current, proposed: proposal.fields);
    if (diffs.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      color: AppTheme.proposal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ai.proposalBadge'.tr()),
          const SizedBox(height: 4),
          for (final d in diffs)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'ai.diffLine'.tr(
                  namedArgs: {
                    'field': d.fieldKey.tr(),
                    'current': d.current.isEmpty
                        ? 'ai.emptyValue'.tr()
                        : d.current,
                    'proposed': d.proposed,
                  },
                ),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: () async {
                  final ctrl =
                      ref.read(carpetaControllerProvider(target).notifier);
                  await ctrl.setEnabled(templateKey, true);
                  for (final e in proposal.fields.entries) {
                    ctrl.setField(templateKey, e.key, e.value);
                    fields[e.key]?.text = e.value;
                  }
                  await discardAiDraft(proposal.draftId);
                  ref.read(aiPrefillProvider.notifier).state = null;
                  ref.invalidate(liveAiDraftsProvider(clienteId));
                },
                child: Text('ai.apply'.tr()),
              ),
              TextButton(
                onPressed: () async {
                  await discardAiDraft(proposal.draftId);
                  ref.read(aiPrefillProvider.notifier).state = null;
                  ref.invalidate(liveAiDraftsProvider(clienteId));
                },
                child: Text('ai.discard'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DocumentoForm extends ConsumerWidget {
  const _DocumentoForm({
    required this.target,
    required this.templateKey,
    required this.doc,
    required this.clienteNombre,
    required this.onOpen,
    required this.onRemove,
  });

  final CarpetaTarget target;
  final String templateKey;
  final CarpetaDocumento doc;
  final String clienteNombre;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts =
        ref.watch(liveAiDraftsProvider(target.clienteId)).valueOrNull ??
            const [];
    final memory = ref.watch(aiPrefillProvider);
    AiPrefillDraft? pending;
    if (memory != null && memory.storagePath == doc.storagePath) {
      pending = memory;
    } else {
      for (final d in drafts) {
        if (d.storagePath == doc.storagePath) {
          pending = d;
          break;
        }
      }
    }
    final values = pending?.fields ?? doc.extracted;
    final keys = fieldsForDocTipo(doc.tipo);
    final shown = [
      for (final k in keys)
        if ((values[k] ?? '').trim().isNotEmpty) k,
    ];
    final nombre = (values['fields.nombre'] ?? '').trim();
    final mismatch =
        nombre.isNotEmpty && !namesLikelyMatch(clienteNombre, nombre);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: pending != null ? AppTheme.proposal : AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: AppTheme.rule),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_outlined, size: 18),
                title: Text(doc.originalName),
                subtitle: Text('docs.${doc.tipo}'.tr()),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'folder.open'.tr(),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      onPressed: onOpen,
                    ),
                    IconButton(
                      tooltip: 'folder.remove'.tr(),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: onRemove,
                    ),
                  ],
                ),
              ),
              if (mismatch)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'folder.nameMismatch'.tr(
                      namedArgs: {
                        'doc': nombre,
                        'card': clienteNombre,
                      },
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              for (final k in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('${k.tr()}: ${values[k]}'),
                ),
              if (pending != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: () async {
                      final draft = pending!;
                      final ctrl = ref.read(
                        carpetaControllerProvider(target).notifier,
                      );
                      await ctrl.saveDocumentoExtracted(
                        templateKey: templateKey,
                        documentId: doc.id,
                        fields: draft.fields,
                      );
                      await discardAiDraft(draft.draftId);
                      ref.read(aiPrefillProvider.notifier).state = null;
                      ref.invalidate(liveAiDraftsProvider(target.clienteId));
                    },
                    child: Text('ai.apply'.tr()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

