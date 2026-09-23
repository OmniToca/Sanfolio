import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/documents/office_attach_button.dart';
import '../../core/documents/office_file_pick.dart';
import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../ai/ai_providers.dart';
import '../ai/extract_queue.dart';
import 'carpeta_controller.dart';
import 'carpeta_routes.dart';
import 'stoh.dart';
import 'stoh_queue.dart';

/// Sklad skenů u klienta. AI navrhne blok, Guardar zařadí.
class StohScreen extends ConsumerStatefulWidget {
  const StohScreen({
    super.key,
    required this.clienteId,
    this.expedienteId,
    this.afterCreate = false,
  });

  final String clienteId;
  final String? expedienteId;
  final bool afterCreate;

  @override
  ConsumerState<StohScreen> createState() => _StohScreenState();
}

class _StohScreenState extends ConsumerState<StohScreen> {
  final _bloqueChoice = <String, String>{};
  final _tipoChoice = <String, String>{};
  final _queue = <PickedOfficeFile>[];
  var _uploading = false;
  var _uploadDone = 0;
  var _uploadTotal = 0;
  var _draining = false;

  CarpetaTarget get _target => CarpetaTarget(
        clienteId: widget.clienteId,
        expedienteId: widget.expedienteId,
      );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(carpetaControllerProvider(_target));
    final drafts = ref.watch(liveAiDraftsProvider(widget.clienteId));
    return Scaffold(
      appBar: AppBar(
        title: Text('stoh.title'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(
            carpetaRoute(widget.clienteId, expedienteId: widget.expedienteId),
          ),
        ),
      ),
      body: FeatureGate(
        module: GestoriaModule.carpetaInmueble,
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(child: Text('folder.loadError'.tr())),
          data: (view) {
            final rows = mergeStohQueue(
              documents: view.stohDocuments,
              drafts: drafts.valueOrNull ?? const [],
            );
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppTheme.contentWide,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppPageHeader(
                        title: view.nombre.isEmpty
                            ? 'stoh.title'.tr()
                            : view.nombre,
                        subtitle: widget.afterCreate
                            ? 'stoh.newHint'.tr()
                            : 'stoh.subtitle'.tr(),
                        actions: [_attachButton()],
                      ),
                      Text(
                        'stoh.hint'.tr(),
                        style: const TextStyle(
                          color: AppTheme.pencil,
                          fontSize: 13,
                        ),
                      ),
                      if (widget.afterCreate)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => context.go(
                                carpetaRoute(
                                  widget.clienteId,
                                  expedienteId: widget.expedienteId,
                                ),
                              ),
                              child: Text('stoh.skip'.tr()),
                            ),
                          ),
                        ),
                      if (_uploading) _uploadProgress(),
                      Expanded(
                        child: rows.isEmpty && !_uploading
                            ? Padding(
                                padding: const EdgeInsets.only(top: 48),
                                child: Text('stoh.empty'.tr()),
                              )
                            : ListView(
                                padding: const EdgeInsets.only(
                                  top: 16,
                                  bottom: 48,
                                ),
                                children: [
                                  for (final row in rows)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 16),
                                      child: _StohCard(
                                        row: row,
                                        view: view,
                                        bloque: _bloqueChoice[row.document.id] ??
                                            row.proposal.bloqueKey,
                                        tipo: _tipoChoice[row.document.id] ??
                                            row.proposal.tipo,
                                        onBloque: (v) => setState(() {
                                          _bloqueChoice[row.document.id] = v;
                                          _tipoChoice[row.document.id] =
                                              tiposForStohBloque(v).first;
                                        }),
                                        onTipo: (v) => setState(
                                          () => _tipoChoice[row.document.id] = v,
                                        ),
                                        onGuardar: () => _guardar(row, view),
                                        onDiscard: () => _discard(row),
                                        onOpen: () =>
                                            _open(row.document.storagePath),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _uploadProgress() {
    final percent = stohUploadPercent(
      done: _uploadDone,
      total: _uploadTotal,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'stoh.progress'.tr(
                    namedArgs: {
                      'done': '$_uploadDone',
                      'total': '$_uploadTotal',
                    },
                  ),
                ),
              ),
              Text(
                'stoh.percent'.tr(
                  namedArgs: {'percent': '$percent'},
                ),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: stohUploadFraction(
                done: _uploadDone,
                total: _uploadTotal,
              ),
              minHeight: 8,
              color: AppTheme.accent,
              backgroundColor: AppTheme.accentSoft,
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachButton() {
    return OfficeAttachButton(
      label: 'stoh.attach'.tr(),
      icon: Icons.file_upload_outlined,
      outlined: true,
      multiple: true,
      onPickedMany: _enqueue,
    );
  }

  Future<void> _enqueue(List<PickedOfficeFile> files) async {
    if (files.isEmpty) return;
    final room = kStohBatchMax - _uploadDone - _queue.length;
    if (room <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('stoh.tooMany'.tr())),
        );
      }
      return;
    }
    final accepted = files.take(room).toList();
    if (accepted.length < files.length && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('stoh.tooMany'.tr())),
      );
    }
    _queue.addAll(accepted);
    if (_draining) {
      if (mounted) {
        setState(() => _uploadTotal = _uploadDone + _queue.length);
      }
      return;
    }
    await _drain();
  }

  Future<void> _drain() async {
    _draining = true;
    if (mounted) {
      setState(() {
        _uploading = true;
        _uploadTotal = _uploadDone + _queue.length;
      });
    }
    final view = ref.read(carpetaControllerProvider(_target)).valueOrNull;
    if (view == null) {
      _queue.clear();
      _draining = false;
      _uploadDone = 0;
      _uploadTotal = 0;
      if (mounted) setState(() => _uploading = false);
      return;
    }
    final ctrl = ref.read(carpetaControllerProvider(_target).notifier);
    while (_queue.isNotEmpty) {
      final file = _queue.removeAt(0);
      try {
        final doc = await ctrl.attachStohDocument(
          bytes: file.bytes,
          originalName: file.name,
        );
        if (doc != null) {
          startExtractInBackground(
            tenantId: view.tenantId,
            clienteId: view.clienteId,
            storagePath: doc.storagePath,
            mime: mimeForOfficeFile(file.name, extension: file.extension),
            classify: true,
          );
        }
      } on Object catch (e) {
        if (mounted) showOfficeUploadFailure(context, e);
      }
      if (mounted) {
        setState(() {
          _uploadDone += 1;
          _uploadTotal = _uploadDone + _queue.length;
        });
      }
    }
    ref.invalidate(liveAiDraftsProvider(widget.clienteId));
    _draining = false;
    _uploadDone = 0;
    _uploadTotal = 0;
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _guardar(StohQueueRow row, CarpetaView view) async {
    final bloque = _bloqueChoice[row.document.id] ?? row.proposal.bloqueKey;
    final tipo = _tipoChoice[row.document.id] ?? row.proposal.tipo;
    if (row.pending || planStohGuardar(
          selectedBloqueKey: bloque,
          selectedTipo: tipo,
          bloqueCurrentlyEnabled: view.bloques[bloque]?.enabled ?? false,
        ) ==
        null) {
      return;
    }
    final ctrl = ref.read(carpetaControllerProvider(_target).notifier);
    final ok = await ctrl.guardarStohDocumento(
      documentId: row.document.id,
      bloqueKey: bloque,
      tipo: tipo,
      fields: row.fields,
      draftId: row.draftId,
    );
    if (!mounted) return;
    ref.invalidate(liveAiDraftsProvider(widget.clienteId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'stoh.saved'.tr() : 'stoh.saveError'.tr()),
      ),
    );
  }

  Future<void> _discard(StohQueueRow row) async {
    final ctrl = ref.read(carpetaControllerProvider(_target).notifier);
    await ctrl.discardStohDocumento(
      documentId: row.document.id,
      draftId: row.draftId,
    );
    ref.invalidate(liveAiDraftsProvider(widget.clienteId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('stoh.discarded'.tr())),
    );
  }

  Future<void> _open(String path) async {
    final ctrl = ref.read(carpetaControllerProvider(_target).notifier);
    final url = await ctrl.signedUrl(path);
    if (url == null || url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('folder.openError'.tr())),
        );
      }
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

class _StohCard extends StatelessWidget {
  const _StohCard({
    required this.row,
    required this.view,
    required this.bloque,
    required this.tipo,
    required this.onBloque,
    required this.onTipo,
    required this.onGuardar,
    required this.onDiscard,
    required this.onOpen,
  });

  final StohQueueRow row;
  final CarpetaView view;
  final String bloque;
  final String tipo;
  final ValueChanged<String> onBloque;
  final ValueChanged<String> onTipo;
  final VoidCallback onGuardar;
  final VoidCallback onDiscard;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tipos = tiposForStohBloque(bloque.isEmpty ? 'agua' : bloque);
    final canSave = !row.pending &&
        planStohGuardar(
              selectedBloqueKey: bloque,
              selectedTipo: tipo,
              bloqueCurrentlyEnabled: view.bloques[bloque]?.enabled ?? false,
            ) !=
            null;
    final proposal = extractProposalFields(row.fields);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              row.document.originalName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (row.pending)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('stoh.pending'.tr()),
              ),
            if (row.failed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('stoh.failed'.tr()),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('stoh-b-${row.document.id}-$bloque'),
              initialValue: bloque.isEmpty ? null : bloque,
              decoration: InputDecoration(labelText: 'stoh.bloque'.tr()),
              hint: Text('stoh.unknown'.tr()),
              items: [
                for (final key in kStohBloqueOrder)
                  DropdownMenuItem(
                    value: key,
                    child: Text('blocks.$key'.tr()),
                  ),
              ],
              onChanged: row.pending
                  ? null
                  : (v) {
                      if (v != null) onBloque(v);
                    },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('stoh-t-${row.document.id}-$tipo-$bloque'),
              initialValue: tipos.contains(tipo) ? tipo : tipos.first,
              decoration: InputDecoration(labelText: 'stoh.tipo'.tr()),
              items: [
                for (final t in tipos)
                  DropdownMenuItem(
                    value: t,
                    child: Text('docs.$t'.tr()),
                  ),
              ],
              onChanged: row.pending || bloque.isEmpty
                  ? null
                  : (v) {
                      if (v != null) onTipo(v);
                    },
            ),
            if (proposal.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  proposal.entries
                      .take(6)
                      .map((e) => '${e.key}: ${e.value}')
                      .join(' · '),
                  style: const TextStyle(
                    color: AppTheme.pencil,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: canSave ? onGuardar : null,
                  child: Text('stoh.guardar'.tr()),
                ),
                TextButton(
                  onPressed: onOpen,
                  child: Text('folder.original'.tr()),
                ),
                TextButton(
                  onPressed: onDiscard,
                  child: Text('stoh.discardFile'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
