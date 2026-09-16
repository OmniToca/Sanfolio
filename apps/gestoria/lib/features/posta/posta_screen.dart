import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import 'posta_address.dart';
import 'posta_providers.dart';
import 'posta_timeline.dart';

/// Třídírna pracovní pošty. Gmail zůstává na odpověď.
class PostaScreen extends ConsumerStatefulWidget {
  const PostaScreen({super.key, this.initialId});

  final String? initialId;

  @override
  ConsumerState<PostaScreen> createState() => _PostaScreenState();
}

class _PostaScreenState extends ConsumerState<PostaScreen> {
  String? _selectedId;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialId;
  }

  @override
  Widget build(BuildContext context) {
    return FeatureGate(
      module: GestoriaModule.messaging,
      fallback: Scaffold(
        appBar: AppBar(title: Text('posta.title'.tr())),
        body: Center(child: Text('posta.moduleOff'.tr())),
      ),
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final list = ref.watch(postaListProvider);
            return list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('posta.loadError'.tr())),
              data: (rows) {
                final selectedId = _selectedId ??
                    (rows.isEmpty ? null : rows.first.id);
                if (wide) {
                  return Row(
                    children: [
                      SizedBox(
                        width: 380,
                        child: _PostaListPane(
                          rows: rows,
                          selectedId: selectedId,
                          onSelect: (id) => setState(() => _selectedId = id),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: selectedId == null
                            ? Center(child: Text('posta.empty'.tr()))
                            : _PostaDetailPane(
                                messageId: selectedId,
                                busy: _busy,
                                onAssign: () => _assign(selectedId),
                                onAssignHit: (hit) =>
                                    _assignHit(selectedId, hit),
                                onIgnore: () => _ignore(selectedId),
                                onUnassign: () => _unassign(selectedId),
                                onFile: (att, msg) => _file(att, msg),
                                onReply: (msg) => _reply(msg),
                              ),
                      ),
                    ],
                  );
                }
                if (selectedId != null && _selectedId != null) {
                  return _PostaDetailPane(
                    messageId: selectedId,
                    busy: _busy,
                    onBack: () => setState(() => _selectedId = null),
                    onAssign: () => _assign(selectedId),
                    onAssignHit: (hit) => _assignHit(selectedId, hit),
                    onIgnore: () => _ignore(selectedId),
                    onUnassign: () => _unassign(selectedId),
                    onFile: (att, msg) => _file(att, msg),
                    onReply: (msg) => _reply(msg),
                  );
                }
                return _PostaListPane(
                  rows: rows,
                  selectedId: selectedId,
                  onSelect: (id) => setState(() => _selectedId = id),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _assign(String messageId) async {
    final hit = await showDialog<PostaClienteHit>(
      context: context,
      builder: (ctx) => const _PostaClienteDialog(),
    );
    if (hit == null) return;
    await _assignHit(messageId, hit);
  }

  Future<void> _assignHit(String messageId, PostaClienteHit hit) async {
    setState(() => _busy = true);
    try {
      await assignPostaMessage(messageId: messageId, clienteId: hit.id);
      _invalidate();
    } on Object {
      if (mounted) _toast('posta.assignError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reply(PostaMessage msg) {
    final clienteId = msg.clienteId;
    if (clienteId == null || clienteId.isEmpty) return;
    context.go('/clientes/$clienteId/mensaje?posta=${msg.id}');
  }

  Future<void> _ignore(String messageId) async {
    setState(() => _busy = true);
    try {
      await ignorePostaMessage(messageId);
      setState(() => _selectedId = null);
      _invalidate();
    } on Object {
      if (mounted) _toast('posta.ignoreError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unassign(String messageId) async {
    setState(() => _busy = true);
    try {
      await unassignPostaMessage(messageId);
      _invalidate();
    } on Object {
      if (mounted) _toast('posta.assignError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _file(PostaAttachment att, PostaMessage msg) async {
    var clienteId = msg.clienteId;
    if (clienteId == null || clienteId.isEmpty) {
      final hit = await showDialog<PostaClienteHit>(
        context: context,
        builder: (ctx) => const _PostaClienteDialog(),
      );
      if (hit == null) return;
      await assignPostaMessage(messageId: msg.id, clienteId: hit.id);
      clienteId = hit.id;
    }
    final targets = await loadPostaFileTargets(clienteId);
    if (!mounted) return;
    final target = await showDialog<PostaFileTarget>(
      context: context,
      builder: (ctx) => _PostaFileDialog(targets: targets),
    );
    if (target == null) return;
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    if (tenantId == null) return;
    setState(() => _busy = true);
    try {
      await filePostaAttachment(
        tenantId: tenantId,
        clienteId: clienteId,
        attachment: att,
        target: target,
        createdBy: ref.read(authControllerProvider).valueOrNull?.profile?.id,
      );
      _invalidate();
      if (mounted) _toast('posta.filedExtract'.tr());
    } on Object {
      if (mounted) _toast('posta.fileError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _invalidate() {
    ref.invalidate(postaListProvider);
    ref.invalidate(postaUnassignedCountProvider);
    ref.invalidate(postaUnfiledCountProvider);
    ref.invalidate(clienteMailTimelineProvider);
    final id = _selectedId;
    if (id != null) ref.invalidate(postaDetailProvider(id));
    ref.invalidate(clientePostaProvider);
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _PostaListPane extends ConsumerWidget {
  const _PostaListPane({
    required this.rows,
    required this.selectedId,
    required this.onSelect,
  });

  final List<PostaMessage> rows;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  static const _filters = [
    'unassigned',
    'unfiled',
    'attachments',
    'assigned',
    'all',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(postaFilterProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
      children: [
        AppPageHeader(
          title: 'posta.title'.tr(),
          subtitle: 'posta.subtitle'.tr(),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final key in _filters)
              AppStamp(
                label: 'posta.filter.$key'.tr(),
                selected: filter == key,
                onTap: () =>
                    ref.read(postaFilterProvider.notifier).state = key,
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Text(
              'posta.empty'.tr(),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppTheme.pencil,
                  ),
            ),
          )
        else
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                emphasized: row.id == selectedId,
                stripe: (row.status == 'unassigned' && row.hasAttachments) ||
                        (row.status == 'assigned' && row.hasUnfiled)
                    ? AppTheme.statusWarn
                    : null,
                onTap: () => onSelect(row.id),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.fromLabel,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        row.subject?.isNotEmpty == true
                            ? row.subject!
                            : 'posta.noSubject'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          DateFormat.yMMMd(context.locale.toString())
                              .add_Hm()
                              .format(row.receivedAt.toLocal()),
                          'posta.status.${row.status}'.tr(),
                          if (row.clienteNombre != null) row.clienteNombre!,
                          if (row.hasAttachments)
                            'posta.attachCount'.tr(
                              namedArgs: {
                                'count': '${row.attachments.length}',
                              },
                            ),
                          if (row.hasUnfiled)
                            'posta.unfiledCount'.tr(
                              namedArgs: {'count': '${row.unfiledCount}'},
                            ),
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.pencil,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _PostaDetailPane extends ConsumerWidget {
  const _PostaDetailPane({
    required this.messageId,
    required this.busy,
    required this.onAssign,
    required this.onAssignHit,
    required this.onIgnore,
    required this.onUnassign,
    required this.onFile,
    required this.onReply,
    this.onBack,
  });

  final String messageId;
  final bool busy;
  final VoidCallback onAssign;
  final ValueChanged<PostaClienteHit> onAssignHit;
  final VoidCallback onIgnore;
  final VoidCallback onUnassign;
  final Future<void> Function(PostaAttachment att, PostaMessage msg) onFile;
  final ValueChanged<PostaMessage> onReply;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(postaDetailProvider(messageId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('posta.loadError'.tr())),
      data: (msg) {
        if (msg == null) {
          return Center(child: Text('posta.empty'.tr()));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
          children: [
            if (onBack != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: Text('posta.back'.tr()),
                ),
              ),
            Text(
              msg.subject?.isNotEmpty == true
                  ? msg.subject!
                  : 'posta.noSubject'.tr(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '${msg.fromLabel} · ${msg.fromAddress}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (msg.assigned) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: () => context.go('/clientes/${msg.clienteId}'),
                child: Text(
                  msg.clienteNombre ?? 'posta.assigned'.tr(),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppTheme.accent,
                      ),
                ),
              ),
            ],
            if (msg.matchMethod != null) ...[
              const SizedBox(height: 4),
              Text(
                'posta.match.${msg.matchMethod}'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.pencil,
                    ),
              ),
            ],
            if (!msg.assigned) ...[
              const SizedBox(height: 12),
              _PostaSuggestCard(
                messageId: messageId,
                busy: busy,
                onConfirm: onAssignHit,
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: busy ? null : onAssign,
                  child: Text('posta.assign'.tr()),
                ),
                if (msg.assigned)
                  FilledButton.tonal(
                    onPressed: busy ? null : () => onReply(msg),
                    child: Text('posta.reply'.tr()),
                  ),
                if (msg.assigned)
                  OutlinedButton(
                    onPressed: busy ? null : onUnassign,
                    child: Text('posta.unassign'.tr()),
                  ),
                OutlinedButton(
                  onPressed: busy ? null : onIgnore,
                  child: Text('posta.ignore'.tr()),
                ),
                if (msg.openInGmail != null)
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse(msg.openInGmail!)),
                    child: Text('posta.openGmail'.tr()),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'posta.attachments'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (msg.attachments.isEmpty)
              Text(
                'posta.noAttachments'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.pencil,
                    ),
              )
            else
              for (final att in msg.attachments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(att.filename),
                  subtitle: Text(
                    att.filed
                        ? 'posta.alreadyFiled'.tr()
                        : (att.mime ?? ''),
                  ),
                  trailing: att.filed
                      ? IconButton(
                          tooltip: 'folder.open'.tr(),
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () async {
                            try {
                              final url = await signedPostaUrl(att.storagePath);
                              await launchUrl(Uri.parse(url));
                            } on Object {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('folder.openError'.tr()),
                                  ),
                                );
                              }
                            }
                          },
                        )
                      : FilledButton(
                          onPressed: busy ? null : () => onFile(att, msg),
                          child: Text('posta.file'.tr()),
                        ),
                ),
            const SizedBox(height: 24),
            _PostaBody(text: msg.bodyText),
          ],
        );
      },
    );
  }
}

/// Tělo mailu jde označit a zkopírovat; URL jsou tlačítka (Flutter Text nejde klikat).
class _PostaBody extends StatelessWidget {
  const _PostaBody({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final body = text?.trim() ?? '';
    if (body.isEmpty) {
      return Text('posta.noBody'.tr());
    }
    final urls = extractHttpUrls(body);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                body,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            IconButton(
              tooltip: 'posta.copyBody'.tr(),
              icon: const Icon(Icons.copy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: body));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('posta.copiedBody'.tr())),
                );
              },
            ),
          ],
        ),
        if (urls.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'posta.links'.tr(),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          for (final url in urls)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => launchUrl(Uri.parse(url)),
                  child: Text(url, textAlign: TextAlign.left),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _PostaSuggestCard extends ConsumerWidget {
  const _PostaSuggestCard({
    required this.messageId,
    required this.busy,
    required this.onConfirm,
  });

  final String messageId;
  final bool busy;
  final ValueChanged<PostaClienteHit> onConfirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(postaSuggestProvider(messageId));
    return async.maybeWhen(
      data: (hit) {
        if (hit == null) return const SizedBox.shrink();
        return AppCard(
          stripe: AppTheme.accent,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(
              'posta.suggest'.tr(namedArgs: {'name': hit.nombre}),
            ),
            subtitle: Text(
              [
                if (hit.matchMethod != null)
                  'posta.match.${hit.matchMethod}'.tr(),
                'posta.suggestHint'.tr(),
              ].join(' '),
            ),
            trailing: FilledButton(
              onPressed: busy ? null : () => onConfirm(hit),
              child: Text('posta.assign'.tr()),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _PostaClienteDialog extends ConsumerStatefulWidget {
  const _PostaClienteDialog();

  @override
  ConsumerState<_PostaClienteDialog> createState() =>
      _PostaClienteDialogState();
}

class _PostaClienteDialogState extends ConsumerState<_PostaClienteDialog> {
  final _q = TextEditingController();
  var _hits = const <PostaClienteHit>[];
  var _loading = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final hits = await searchPostaClientes(q);
      if (mounted) setState(() => _hits = hits);
    } on Object {
      if (mounted) setState(() => _hits = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('posta.pickClient'.tr()),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _q,
              decoration: InputDecoration(
                labelText: 'posta.searchClient'.tr(),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                if (v.trim().length >= 2) _search(v);
              },
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (_hits.isEmpty && _q.text.trim().length >= 2 && !_loading)
                    ListTile(title: Text('posta.noClient'.tr())),
                  for (final hit in _hits)
                    ListTile(
                      title: Text(hit.nombre),
                      subtitle: hit.subtitle.isEmpty ? null : Text(hit.subtitle),
                      onTap: () => Navigator.pop(context, hit),
                    ),
                ],
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

class _PostaFileDialog extends StatelessWidget {
  const _PostaFileDialog({required this.targets});

  final List<PostaFileTarget> targets;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('posta.fileTo'.tr()),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in targets)
              ListTile(
                title: Text(t.labelKey.tr()),
                onTap: () => Navigator.pop(context, t),
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
