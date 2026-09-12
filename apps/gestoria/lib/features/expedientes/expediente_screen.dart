import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/staff_role.dart';

import '../../core/presentation/widgets/app_widgets.dart';
import '../carpeta/carpeta_controller.dart';
import 'expediente_controller.dart';
import 'expediente_estado.dart';
import '../inbox/inbox_providers.dart';

class ExpedienteScreen extends ConsumerStatefulWidget {
  const ExpedienteScreen({super.key, required this.expedienteId});

  final String expedienteId;

  @override
  ConsumerState<ExpedienteScreen> createState() => _ExpedienteScreenState();
}

class _ExpedienteScreenState extends ConsumerState<ExpedienteScreen> {
  final _controllers = <String, TextEditingController>{};
  var _filledFor = '';
  var _busy = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(String key, String value) {
    return _controllers.putIfAbsent(key, () => TextEditingController(text: value));
  }

  void _fill(ThinExpedienteView view) {
    if (_filledFor == view.id) return;
    _filledFor = view.id;
    for (final key in view.kind.fieldKeys) {
      _ctrl(key, view.bloque.values[key] ?? '').text =
          view.bloque.values[key] ?? '';
    }
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
        _fill(view);
        final ctrl =
            ref.read(thinExpedienteProvider(widget.expedienteId).notifier);
        final auth = ref.watch(authControllerProvider).valueOrNull;
        final canDelete = auth != null && canSoftDeleteExpediente(auth);
        return Scaffold(
          appBar: AppBar(
            title: Text('expedientes.tipo.${view.kind.tipo}'.tr()),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/clientes/${view.clienteId}'),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('expedientes.intro'.tr()),
              const SizedBox(height: 8),
              ExpedienteEstadoPicker(
                estado: view.estado,
                onChanged: (v) async {
                  await setExpedienteEstado(
                    expedienteId: view.id,
                    estado: v,
                  );
                  ref.invalidate(thinExpedienteProvider(widget.expedienteId));
                  ref.invalidate(inboxFeedProvider);
                },
              ),
              const SizedBox(height: 8),
              Text(statusLabel(statusOf(view.kind.template, view.bloque))),
              const SizedBox(height: 16),
              for (final key in view.kind.fieldKeys) ...[
                _field(view, key, ctrl),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text('clients.save'.tr()),
              ),
              if (view.kind.requiredDocTypes.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'folder.requiredDocs'.tr(
                    namedArgs: {
                      'types': view.kind.requiredDocTypes
                          .map((t) => 'docs.$t'.tr())
                          .join(', '),
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy ? null : _pickAndAttach,
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: Text('folder.attach'.tr()),
                  ),
                ),
                for (final doc in view.bloque.documents)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(
                      doc.originalName.isEmpty
                          ? 'docs.${doc.tipo}'.tr()
                          : doc.originalName,
                    ),
                    subtitle: Text('docs.${doc.tipo}'.tr()),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'folder.open'.tr(),
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () => _openDoc(doc.storagePath),
                        ),
                        IconButton(
                          tooltip: 'folder.remove'.tr(),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _busy ? null : () => _removeDoc(doc.id),
                        ),
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
        );
      },
    );
  }

  Widget _field(
    ThinExpedienteView view,
    String key,
    ThinExpedienteController ctrl,
  ) {
    final value = view.bloque.values[key] ?? '';
    if (key == 'fields.periodicity') {
      return DropdownMenu<String>(
        key: ValueKey('periodicity-$value'),
        initialSelection: value.isEmpty ? null : value,
        label: Text(key.tr()),
        expandedInsets: EdgeInsets.zero,
        dropdownMenuEntries: [
          DropdownMenuEntry(
            value: 'trimestral',
            label: 'expedientes.periodicidad.trimestral'.tr(),
          ),
          DropdownMenuEntry(
            value: 'anual',
            label: 'expedientes.periodicidad.anual'.tr(),
          ),
        ],
        onSelected: (v) {
          if (v == null) return;
          ctrl.setField(key, v);
        },
      );
    }
    if (key == 'fields.nieStatus') {
      return DropdownMenu<String>(
        key: ValueKey('nie-$value'),
        initialSelection: value.isEmpty ? null : value,
        label: Text(key.tr()),
        expandedInsets: EdgeInsets.zero,
        dropdownMenuEntries: [
          for (final st in const ['cita', 'presentado', 'resuelto', 'rechazado'])
            DropdownMenuEntry(
              value: st,
              label: 'expedientes.nieStatus.$st'.tr(),
            ),
        ],
        onSelected: (v) {
          if (v == null) return;
          ctrl.setField(key, v);
        },
      );
    }
    return AppTextField(
      label: key.tr(),
      controller: _ctrl(key, value),
      onChanged: (v) => ctrl.setField(key, v),
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

  Future<void> _pickAndAttach() async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _toast('folder.uploadError'.tr());
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(thinExpedienteProvider(widget.expedienteId).notifier)
          .attachDocument(bytes: bytes, originalName: file.name);
    } on Object {
      if (mounted) _toast('folder.uploadError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDoc(String path) async {
    try {
      final url = await ref
          .read(thinExpedienteProvider(widget.expedienteId).notifier)
          .signedUrl(path);
      if (url == null) throw StateError('url');
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
