import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/documents/documento_storage.dart';
import '../../core/documents/office_attach_button.dart';
import '../../core/documents/office_file_pick.dart';
import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../ai/ai_providers.dart';
import 'carpeta_controller.dart';
import 'carpeta_routes.dart';
import 'documento_library.dart';
import 'library_view.dart';
import 'stoh.dart';
import 'stoh_queue.dart';

/// Knihovna skenů u klienta. AI zařadí album, desku ukládá gestor.
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
  final _selected = <String>{};
  final _search = TextEditingController();
  var _uploading = false;
  var _uploadDone = 0;
  var _uploadTotal = 0;
  var _draining = false;
  var _scope = LibraryScope.all;
  String? _inmuebleId;
  var _query = '';

  CarpetaTarget get _target => CarpetaTarget(
        clienteId: widget.clienteId,
        expedienteId: widget.expedienteId,
      );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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
            final queue = mergeStohQueue(
              documents: view.libraryDocuments.isEmpty
                  ? view.stohDocuments
                  : view.libraryDocuments,
              drafts: drafts.valueOrNull ?? const [],
            );
            final allPapers = buildLibraryPapers(
              documents: view.libraryDocuments.isEmpty
                  ? view.stohDocuments
                  : view.libraryDocuments,
              drafts: queue,
              inmuebles: view.inmuebles,
            );
            final papers = filterLibraryPapers(
              papers: allPapers,
              scope: _scope,
              inmuebleId: _inmuebleId,
              query: _query,
            );
            final pile = groupPilePapers(papers);
            final placed = [for (final p in papers) if (!p.onPile) p];
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
                      if (_uploading)
                        _uploadProgress()
                      else
                        const SizedBox.shrink(),
                      const SizedBox(height: 16),
                      OfficeAttachButton(
                        key: const ValueKey('stoh-attach'),
                        label: 'stoh.attach'.tr(),
                        caption: papers.isEmpty && !_uploading
                            ? 'stoh.empty'.tr()
                            : null,
                        icon: Icons.file_upload_outlined,
                        outlined: true,
                        wide: papers.isEmpty && !_uploading,
                        multiple: true,
                        onPickedMany: _enqueue,
                      ),
                      const SizedBox(height: 12),
                      _filters(view, allPapers),
                      if (_selected.isNotEmpty) _bulkBar(view, allPapers),
                      if (papers.isNotEmpty)
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.only(top: 12, bottom: 48),
                            children: [
                              for (final e in pile.entries) ...[
                                _groupTitle(_groupLabel(e.key)),
                                for (final row in e.value)
                                  _paperCard(row, view),
                              ],
                              if (placed.isNotEmpty &&
                                  _scope != LibraryScope.pile) ...[
                                if (pile.isNotEmpty)
                                  _groupTitle('stoh.filterPlaced'.tr()),
                                for (final row in placed)
                                  _paperCard(row, view),
                              ],
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

  Widget _filters(CarpetaView view, List<LibraryPaper> papers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'stoh.searchHint'.tr(),
          prefixIcon: const Icon(Icons.search),
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final scope in LibraryScope.values)
              AppStamp(
                label: _scopeLabel(scope),
                selected: _scope == scope,
                onTap: () => setState(() => _scope = scope),
              ),
            for (final inm in view.inmuebles)
              AppStamp(
                label: _fincaChip(inm, papers),
                selected: _inmuebleId == inm.id,
                onTap: () => setState(() {
                  _inmuebleId = _inmuebleId == inm.id ? null : inm.id;
                }),
              ),
          ],
        ),
      ],
    );
  }

  String _fincaChip(LibraryInmueble inm, List<LibraryPaper> papers) {
    final label = libraryFincaLabel(inm, papers: papers);
    return label.isEmpty ? 'stoh.unnamedFinca'.tr() : label;
  }

  Widget _bulkBar(CarpetaView view, List<LibraryPaper> papers) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'stoh.selected'.tr(
              namedArgs: {'count': '${_selected.length}'},
            ),
          ),
          TextButton(
            onPressed: () => _bulkPlace(view),
            child: Text('stoh.bulkPlace'.tr()),
          ),
          TextButton(
            onPressed: () => _bulkUnplace(view),
            child: Text('stoh.bulkUnplace'.tr()),
          ),
          if (view.inmuebles.isNotEmpty)
            TextButton(
              onPressed: () => _bulkFinca(view, papers),
              child: Text('stoh.bulkFinca'.tr()),
            ),
          TextButton(
            onPressed: () => _bulkMerge(view),
            child: Text('stoh.merge'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _groupTitle(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppTheme.pencil,
        ),
      ),
    );
  }

  Widget _paperCard(LibraryPaper row, CarpetaView view) {
    final doc = row.document;
    final bloque = _bloqueChoice[doc.id] ??
        (doc.albumKeys.isNotEmpty
            ? doc.albumKeys.first
            : row.proposal.bloqueKey);
    final tipo = _tipoChoice[doc.id] ??
        (doc.tipo != 'other' ? doc.tipo : row.proposal.tipo);
    final checked = _selected.contains(doc.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: checked,
                    onChanged: (_) => setState(() {
                      if (checked) {
                        _selected.remove(doc.id);
                      } else {
                        _selected.add(doc.id);
                      }
                    }),
                  ),
                  Expanded(
                    child: Text(
                      doc.originalName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final key in doc.albumKeys)
                    _chip('blocks.$key'.tr()),
                  if (doc.albumKeys.isEmpty)
                    _chip(
                      row.proposal.known
                          ? 'blocks.${row.proposal.bloqueKey}'.tr()
                          : 'stoh.pile'.tr(),
                    ),
                  _chip(
                    row.inmuebleLabel.isEmpty
                        ? 'stoh.clientPaper'.tr()
                        : row.inmuebleLabel,
                  ),
                  if (row.dupKind != null) _chip(_dupLabel(row.dupKind!)),
                  if (libraryPaperYear(row) > 0)
                    _chip(
                      'stoh.year'.tr(
                        namedArgs: {'year': '${libraryPaperYear(row)}'},
                      ),
                    ),
                ],
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
              ..._glance(row),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('stoh-b-${doc.id}-$bloque'),
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
                        if (v != null) {
                          setState(() {
                            _bloqueChoice[doc.id] = v;
                            _tipoChoice[doc.id] = tiposForStohBloque(v).first;
                          });
                        }
                      },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: row.pending || bloque.isEmpty
                        ? null
                        : () => _place(row, view, bloque, tipo),
                    child: Text('stoh.place'.tr()),
                  ),
                  if (!row.onPile)
                    TextButton(
                      onPressed: () => _unplace(row, view, bloque, tipo),
                      child: Text('stoh.unplace'.tr()),
                    ),
                  TextButton(
                    onPressed: () => _guardar(row, view, bloque, tipo),
                    child: Text('stoh.guardar'.tr()),
                  ),
                  TextButton(
                    onPressed: () => _open(doc.storagePath),
                    child: Text('folder.original'.tr()),
                  ),
                  TextButton(
                    onPressed: () => _discard(row),
                    child: Text('stoh.discardFile'.tr()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _glance(LibraryPaper row) {
    final bits = libraryGlanceEntries(row.glanceFields);
    if (bits.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      Text(
        [
          for (final e in bits) '${e.key.tr()}: ${e.value}',
        ].join(' · '),
        style: const TextStyle(color: AppTheme.pencil, fontSize: 13),
      ),
    ];
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppTheme.pencil),
      ),
    );
  }

  String _scopeLabel(LibraryScope scope) {
    return switch (scope) {
      LibraryScope.all => 'stoh.filterAll'.tr(),
      LibraryScope.pile => 'stoh.filterPile'.tr(),
      LibraryScope.placed => 'stoh.filterPlaced'.tr(),
      LibraryScope.duplicates => 'stoh.filterDup'.tr(),
      LibraryScope.unknown => 'stoh.filterUnknown'.tr(),
    };
  }

  String _groupLabel(String key) {
    if (key == PileGroup.mail.key) return 'stoh.groupMail'.tr();
    if (key == PileGroup.unknown.key) return 'stoh.unknown'.tr();
    if (kStohBloqueKeys.contains(key)) return 'blocks.$key'.tr();
    return key;
  }

  String _dupLabel(DocumentoDupKind kind) {
    return switch (kind) {
      DocumentoDupKind.bytes => 'stoh.dupBytes'.tr(),
      DocumentoDupKind.invoice => 'stoh.dupInvoice'.tr(),
      DocumentoDupKind.name => 'stoh.dupName'.tr(),
    };
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

  Future<void> _place(
    LibraryPaper row,
    CarpetaView view,
    String bloque,
    String tipo,
  ) async {
    final ctrl = ref.read(carpetaControllerProvider(_target).notifier);
    final ok = await ctrl.setLibraryPlacement(
      documentId: row.document.id,
      bloqueKey: bloque,
      tipo: tipo.isEmpty ? row.proposal.tipo : tipo,
      on: true,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'stoh.saved'.tr() : 'stoh.saveError'.tr())),
    );
  }

  Future<void> _unplace(
    LibraryPaper row,
    CarpetaView view,
    String bloque,
    String tipo,
  ) async {
    final key = bloque.isEmpty
        ? (row.document.albumKeys.isEmpty ? '' : row.document.albumKeys.first)
        : bloque;
    if (key.isEmpty) return;
    final ctrl = ref.read(carpetaControllerProvider(_target).notifier);
    await ctrl.setLibraryPlacement(
      documentId: row.document.id,
      bloqueKey: key,
      tipo: tipo,
      on: false,
    );
  }

  Future<void> _guardar(
    LibraryPaper row,
    CarpetaView view,
    String bloque,
    String tipo,
  ) async {
    if (row.pending ||
        planStohGuardar(
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
      fields: row.draftFields,
      draftId: row.draftId,
    );
    if (!mounted) return;
    ref.invalidate(liveAiDraftsProvider(widget.clienteId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'stoh.saved'.tr() : 'stoh.saveError'.tr())),
    );
  }

  Future<void> _discard(LibraryPaper row) async {
    final ctrl = ref.read(carpetaControllerProvider(_target).notifier);
    await ctrl.discardStohDocumento(
      documentId: row.document.id,
      draftId: row.draftId,
    );
    _selected.remove(row.document.id);
    ref.invalidate(liveAiDraftsProvider(widget.clienteId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('stoh.discarded'.tr())),
    );
  }

  Future<void> _bulkPlace(CarpetaView view) async {
    var bloque = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('stoh.bulkPlace'.tr()),
          content: DropdownButtonFormField<String>(
            decoration: InputDecoration(labelText: 'stoh.bloque'.tr()),
            items: [
              for (final key in kStohBloqueOrder)
                DropdownMenuItem(
                  value: key,
                  child: Text('blocks.$key'.tr()),
                ),
            ],
            onChanged: (v) => bloque = v ?? '',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('clients.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('stoh.place'.tr()),
            ),
          ],
        );
      },
    );
    if (ok != true || bloque.isEmpty) return;
    final ctrl = ref.read(carpetaControllerProvider(_target).notifier);
    final ids = _selected.toList();
    for (final id in ids) {
      await ctrl.setLibraryPlacement(
        documentId: id,
        bloqueKey: bloque,
        tipo: tiposForStohBloque(bloque).first,
        on: true,
      );
    }
    if (mounted) setState(() => _selected.clear());
  }

  Future<void> _bulkUnplace(CarpetaView view) async {
    final ctrl = ref.read(carpetaControllerProvider(_target).notifier);
    final ids = _selected.toList();
    for (final id in ids) {
      CarpetaDocumento? doc;
      for (final d in view.libraryDocuments) {
        if (d.id == id) doc = d;
      }
      final key = doc != null && doc.albumKeys.isNotEmpty
          ? doc.albumKeys.first
          : '';
      if (key.isEmpty) continue;
      await ctrl.setLibraryPlacement(
        documentId: id,
        bloqueKey: key,
        tipo: doc?.tipo ?? 'other',
        on: false,
      );
    }
    if (mounted) setState(() => _selected.clear());
  }

  Future<void> _bulkFinca(
    CarpetaView view,
    List<LibraryPaper> papers,
  ) async {
    String? chosen;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('stoh.bulkFinca'.tr()),
          content: DropdownButtonFormField<String>(
            decoration: InputDecoration(labelText: 'stoh.setFinca'.tr()),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text('stoh.noFinca'.tr()),
              ),
              for (final inm in view.inmuebles)
                DropdownMenuItem(
                  value: inm.id,
                  child: Text(_fincaChip(inm, papers)),
                ),
            ],
            onChanged: (v) => chosen = v,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('clients.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('stoh.setFinca'.tr()),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    final ctrl = ref.read(carpetaControllerProvider(_target).notifier);
    final ids = _selected.toList();
    for (final id in ids) {
      await ctrl.setLibraryInmueble(
        documentId: id,
        inmuebleId: (chosen ?? '').isEmpty ? null : chosen,
      );
    }
    if (mounted) setState(() => _selected.clear());
  }

  Future<void> _bulkMerge(CarpetaView view) async {
    final papers = <CarpetaDocumento>[
      for (final id in _selected)
        for (final d in view.libraryDocuments)
          if (d.id == id) d,
    ];
    final reason = libraryMergeBlockReason(
      count: papers.length,
      allImages: papers.every(
        (d) => isLibraryMergeImageName(d.originalName, d.storagePath),
      ),
    );
    if (reason != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(reason.tr())),
        );
      }
      return;
    }
    var order = [...papers];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text('stoh.mergeTitle'.tr()),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('stoh.mergeHint'.tr()),
                    const SizedBox(height: 12),
                    for (var i = 0; i < order.length; i++)
                      ListTile(
                        dense: true,
                        title: Text(order[i].originalName),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'stoh.mergeUp'.tr(),
                              onPressed: i == 0
                                  ? null
                                  : () => setLocal(() {
                                        final a = order[i - 1];
                                        order[i - 1] = order[i];
                                        order[i] = a;
                                      }),
                              icon: const Icon(Icons.arrow_upward),
                            ),
                            IconButton(
                              tooltip: 'stoh.mergeDown'.tr(),
                              onPressed: i == order.length - 1
                                  ? null
                                  : () => setLocal(() {
                                        final a = order[i + 1];
                                        order[i + 1] = order[i];
                                        order[i] = a;
                                      }),
                              icon: const Icon(Icons.arrow_downward),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('clients.cancel'.tr()),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('stoh.mergeRun'.tr()),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    try {
      await ref
          .read(carpetaControllerProvider(_target).notifier)
          .mergeLibraryImages([for (final d in order) d.id]);
      if (mounted) {
        setState(() => _selected.clear());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('stoh.mergeOk'.tr())),
        );
      }
    } on OfficeUploadException catch (e) {
      if (!mounted) return;
      final key = switch (e.code) {
        'need_photos' => 'stoh.mergeNeedPhotos',
        'too_many' => 'stoh.mergeTooMany',
        'duplicate' => 'stoh.duplicateFile',
        _ => 'stoh.mergeError',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(key.tr())),
      );
    }
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
