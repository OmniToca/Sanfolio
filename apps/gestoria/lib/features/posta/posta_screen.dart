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
import '../carpeta/carpeta_routes.dart';
import '../mensajes/mensaje_providers.dart';
import 'posta_address.dart';
import 'posta_html_view.dart';
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
  final _searchFocus = FocusNode();
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialId;
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  bool get _typing {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == _searchFocus) return true;
    final ctx = primary?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  Widget build(BuildContext context) {
    return FeatureGate(
      module: GestoriaModule.messaging,
      fallback: Scaffold(
        appBar: AppBar(title: Text('posta.title'.tr())),
        body: Center(child: Text('posta.moduleOff'.tr())),
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyJ): () => _move(1),
          const SingleActivator(LogicalKeyboardKey.keyK): () => _move(-1),
          const SingleActivator(LogicalKeyboardKey.keyF): _shortcutFile,
          const SingleActivator(LogicalKeyboardKey.keyA): _shortcutAssign,
          const SingleActivator(LogicalKeyboardKey.keyD): _shortcutDone,
          const SingleActivator(LogicalKeyboardKey.keyI): _shortcutIgnore,
          const SingleActivator(LogicalKeyboardKey.keyR): _shortcutReply,
          const SingleActivator(LogicalKeyboardKey.slash): () {
            if (_typing) return;
            _searchFocus.requestFocus();
          },
        },
        child: Focus(
          autofocus: true,
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
                        child:                         _PostaListPane(
                          rows: rows,
                          selectedId: selectedId,
                          search: _search,
                          searchFocus: _searchFocus,
                          onSelect: (id) => setState(() => _selectedId = id),
                          onIgnoreNoise: () => _ignoreNoise(rows),
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
                                onDone: () => _done(selectedId),
                                onUndone: () => _undone(selectedId),
                                onFile: (att, msg, {quick}) =>
                                    _file(att, msg, quick: quick),
                                onFileAll: (msg, {quick}) =>
                                    _fileAll(msg, quick: quick),
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
                    onDone: () => _done(selectedId),
                    onUndone: () => _undone(selectedId),
                    onFile: (att, msg, {quick}) =>
                        _file(att, msg, quick: quick),
                    onFileAll: (msg, {quick}) =>
                        _fileAll(msg, quick: quick),
                    onReply: (msg) => _reply(msg),
                  );
                }
                return _PostaListPane(
                  rows: rows,
                  selectedId: selectedId,
                  search: _search,
                  searchFocus: _searchFocus,
                  onSelect: (id) => setState(() => _selectedId = id),
                  onIgnoreNoise: () => _ignoreNoise(rows),
                );
              },
            );
          },
        ),
          ),
        ),
      ),
    );
  }

  Future<void> _assign(String messageId) async {
    final msg = ref.read(postaDetailProvider(messageId)).valueOrNull;
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    PostaClienteHit? suggested;
    if (msg != null && tenantId != null && !msg.assigned) {
      suggested = await suggestPostaCliente(
        tenantId: tenantId,
        email: msg.fromAddress,
        fromName: msg.fromName,
      );
    }
    if (!mounted) return;
    final hit = await showDialog<PostaClienteHit>(
      context: context,
      builder: (ctx) => _PostaClienteDialog(suggested: suggested),
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

  void _move(int delta) {
    if (_typing) return;
    final rows = ref.read(postaListProvider).valueOrNull ?? const [];
    if (rows.isEmpty) return;
    final current = _selectedId ?? rows.first.id;
    final i = rows.indexWhere((r) => r.id == current);
    final next = (i + delta).clamp(0, rows.length - 1);
    setState(() => _selectedId = rows[next].id);
  }

  void _shortcutFile() {
    if (_typing || _busy) return;
    final id = _selectedId;
    if (id == null) return;
    final msg = ref.read(postaDetailProvider(id)).valueOrNull;
    if (msg == null || !msg.hasUnfiled) return;
    final quick = ref.read(postaQuickFileProvider(id)).valueOrNull;
    _fileAll(msg, quick: quick);
  }

  void _shortcutAssign() {
    if (_typing || _busy) return;
    final id = _selectedId;
    if (id == null) return;
    final hit = ref.read(postaSuggestProvider(id)).valueOrNull;
    if (hit != null) {
      _assignHit(id, hit);
      return;
    }
    _assign(id);
  }

  void _shortcutDone() {
    if (_typing || _busy) return;
    final id = _selectedId;
    if (id == null) return;
    _done(id);
  }

  void _shortcutIgnore() {
    if (_typing || _busy) return;
    final id = _selectedId;
    if (id == null) return;
    _ignore(id);
  }

  void _shortcutReply() {
    if (_typing) return;
    final id = _selectedId;
    if (id == null) return;
    final msg = ref.read(postaDetailProvider(id)).valueOrNull;
    if (msg != null) _reply(msg);
  }

  Future<void> _done(String messageId) async {
    final msg = ref.read(postaDetailProvider(messageId)).valueOrNull;
    if (msg == null) return;
    if (msg.hasUnfiled) {
      _toast('posta.doneNeedFile'.tr());
      return;
    }
    if (!msg.assigned) {
      final tenantId =
          ref.read(authControllerProvider).valueOrNull?.currentTenantId;
      PostaClienteHit? hit;
      if (tenantId != null) {
        hit = await suggestPostaCliente(
          tenantId: tenantId,
          email: msg.fromAddress,
          fromName: msg.fromName,
        );
      }
      if (hit == null) {
        if (!mounted) return;
        await _assign(messageId);
        final again = ref.read(postaDetailProvider(messageId)).valueOrNull;
        if (again == null || !again.assigned) return;
      } else {
        await _assignHit(messageId, hit);
      }
    }
    setState(() => _busy = true);
    try {
      await markPostaDone(messageId);
      _invalidate();
      if (mounted) _toast('posta.markedDone'.tr());
    } on Object {
      if (mounted) _toast('posta.doneError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undone(String messageId) async {
    setState(() => _busy = true);
    try {
      await markPostaUndone(messageId);
      _invalidate();
    } on Object {
      if (mounted) _toast('posta.doneError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  Future<void> _ignoreNoise(List<PostaMessage> rows) async {
    final ids = [
      for (final row in rows)
        if (row.status == 'unassigned' &&
            isPostaNoiseMail(from: row.fromAddress, subject: row.subject))
          row.id,
    ];
    if (ids.isEmpty) return;
    setState(() => _busy = true);
    try {
      for (final id in ids) {
        await ignorePostaMessage(id);
      }
      setState(() => _selectedId = null);
      _invalidate();
      if (mounted) {
        _toast(
          'posta.ignoredNoise'.tr(namedArgs: {'count': '${ids.length}'}),
        );
      }
    } on Object {
      if (mounted) _toast('posta.ignoreError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _file(
    PostaAttachment att,
    PostaMessage msg, {
    PostaQuickFile? quick,
  }) async {
    var clienteId = msg.clienteId;
    var target = quick?.target;
    if (quick != null) {
      clienteId = quick.clienteId;
      if (quick.assignHit != null && !msg.assigned) {
        await assignPostaMessage(
          messageId: msg.id,
          clienteId: quick.clienteId,
        );
      }
    } else {
      if (clienteId == null || clienteId.isEmpty) {
        final tenantId =
            ref.read(authControllerProvider).valueOrNull?.currentTenantId;
        PostaClienteHit? suggested;
        if (tenantId != null) {
          suggested = await suggestPostaCliente(
            tenantId: tenantId,
            email: msg.fromAddress,
            fromName: msg.fromName,
          );
        }
        if (!mounted) return;
        final hit = await showDialog<PostaClienteHit>(
          context: context,
          builder: (ctx) => _PostaClienteDialog(suggested: suggested),
        );
        if (hit == null) return;
        await assignPostaMessage(messageId: msg.id, clienteId: hit.id);
        clienteId = hit.id;
      }
      final tenantHints =
          ref.read(authControllerProvider).valueOrNull?.currentTenantId;
      final remembered = tenantHints == null
          ? null
          : await suggestPostaSenderBlock(
              tenantId: tenantHints,
              email: msg.fromAddress,
            );
      final hints = suggestPostaBloqueKeys(
        filename: att.filename,
        subject: msg.subject ?? '',
        body: msg.bodyText ?? '',
        rememberedKey: remembered,
      );
      final targets = await loadPostaFileTargets(
        clienteId,
        suggestedKeys: hints,
      );
      if (!mounted) return;
      target = await showDialog<PostaFileTarget>(
        context: context,
        builder: (ctx) => _PostaFileDialog(targets: targets),
      );
    }
    if (target == null || clienteId.isEmpty) return;
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
        fromAddress: msg.fromAddress,
      );
      _invalidate();
      if (mounted) _toastFiled(clienteId, target);
    } on Object {
      if (mounted) _toast('posta.fileError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fileAll(
    PostaMessage msg, {
    PostaQuickFile? quick,
  }) async {
    var clienteId = msg.clienteId;
    var target = quick?.target;
    if (quick != null) {
      clienteId = quick.clienteId;
      if (quick.assignHit != null && !msg.assigned) {
        await assignPostaMessage(
          messageId: msg.id,
          clienteId: quick.clienteId,
        );
      }
    } else {
      if (clienteId == null || clienteId.isEmpty) {
        final tenantId =
            ref.read(authControllerProvider).valueOrNull?.currentTenantId;
        PostaClienteHit? suggested;
        if (tenantId != null) {
          suggested = await suggestPostaCliente(
            tenantId: tenantId,
            email: msg.fromAddress,
            fromName: msg.fromName,
          );
        }
        if (!mounted) return;
        final hit = await showDialog<PostaClienteHit>(
          context: context,
          builder: (ctx) => _PostaClienteDialog(suggested: suggested),
        );
        if (hit == null) return;
        await assignPostaMessage(messageId: msg.id, clienteId: hit.id);
        clienteId = hit.id;
      }
      final tenantIdHints =
          ref.read(authControllerProvider).valueOrNull?.currentTenantId;
      final remembered = tenantIdHints == null
          ? null
          : await suggestPostaSenderBlock(
              tenantId: tenantIdHints,
              email: msg.fromAddress,
            );
      final hints = suggestPostaBloqueKeys(
        filename: msg.attachments.map((a) => a.filename).join('\n'),
        subject: msg.subject ?? '',
        body: msg.bodyText ?? '',
        rememberedKey: remembered,
      );
      final targets = await loadPostaFileTargets(
        clienteId,
        suggestedKeys: hints,
      );
      if (!mounted) return;
      target = await showDialog<PostaFileTarget>(
        context: context,
        builder: (ctx) => _PostaFileDialog(targets: targets),
      );
    }
    if (target == null || clienteId.isEmpty) return;
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    if (tenantId == null) return;
    setState(() => _busy = true);
    try {
      await fileAllPostaAttachments(
        tenantId: tenantId,
        clienteId: clienteId,
        msg: msg,
        target: target,
        createdBy: ref.read(authControllerProvider).valueOrNull?.profile?.id,
      );
      _invalidate();
      if (mounted) _toastFiled(clienteId, target);
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
    ref.invalidate(postaBounceCountProvider);
    ref.invalidate(postaBounceListProvider);
    ref.invalidate(postaQuickFileProvider);
    ref.invalidate(clienteMailTimelineProvider);
    ref.invalidate(postaThreadProvider);
    final id = _selectedId;
    if (id != null) {
      ref.invalidate(postaDetailProvider(id));
      ref.invalidate(postaSuggestProvider(id));
    }
    ref.invalidate(clientePostaProvider);
    ref.invalidate(clienteMensajesProvider);
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _toastFiled(String clienteId, PostaFileTarget target) {
    final key = target.templateKey;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('posta.filedExtract'.tr()),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: key == null || key.isEmpty
              ? 'posta.openCard'.tr()
              : 'posta.openDesk'.tr(),
          onPressed: () {
            if (key == null || key.isEmpty) {
              context.go('/clientes/$clienteId');
              return;
            }
            context.go(
              carpetaBloqueRoute(
                clienteId,
                key,
                expedienteId: target.expedienteId,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PostaListPane extends ConsumerWidget {
  const _PostaListPane({
    required this.rows,
    required this.selectedId,
    required this.onSelect,
    required this.onIgnoreNoise,
    required this.search,
    required this.searchFocus,
  });

  final List<PostaMessage> rows;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onIgnoreNoise;
  final TextEditingController search;
  final FocusNode searchFocus;

  static const _filters = [
    'unassigned',
    'unfiled',
    'attachments',
    'assigned',
    'done',
    'all',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(postaFilterProvider);
    final noiseCount = rows
        .where(
          (row) =>
              row.status == 'unassigned' &&
              isPostaNoiseMail(from: row.fromAddress, subject: row.subject),
        )
        .length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
      children: [
        AppPageHeader(
          title: 'posta.title'.tr(),
          subtitle: 'posta.subtitle'.tr(),
        ),
        TextField(
          controller: search,
          focusNode: searchFocus,
          decoration: InputDecoration(
            hintText: 'posta.searchMail'.tr(),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      search.clear();
                      ref.read(postaSearchQueryProvider.notifier).state = '';
                    },
                  ),
          ),
          onChanged: (v) =>
              ref.read(postaSearchQueryProvider.notifier).state = v,
        ),
        const SizedBox(height: 8),
        Text(
          'posta.shortcuts'.tr(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.pencil,
              ),
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
        if (noiseCount > 0) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onIgnoreNoise,
              child: Text(
                'posta.ignoreNoise'.tr(namedArgs: {'count': '$noiseCount'}),
              ),
            ),
          ),
        ],
        const _PostaBounceStrip(),
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
                stripe: isPostaNoiseMail(
                          from: row.fromAddress,
                          subject: row.subject,
                        )
                    ? AppTheme.pencil
                    : (row.isDone
                        ? AppTheme.statusOk
                        : ((row.status == 'unassigned' &&
                                    row.hasAttachments) ||
                                (row.status == 'assigned' && row.hasUnfiled)
                            ? AppTheme.statusWarn
                            : null)),
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
                          if (row.isDone) 'posta.status.done'.tr(),
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
    required this.onDone,
    required this.onUndone,
    required this.onFile,
    required this.onFileAll,
    required this.onReply,
    this.onBack,
  });

  final String messageId;
  final bool busy;
  final VoidCallback onAssign;
  final ValueChanged<PostaClienteHit> onAssignHit;
  final VoidCallback onIgnore;
  final VoidCallback onUnassign;
  final VoidCallback onDone;
  final VoidCallback onUndone;
  final Future<void> Function(
    PostaAttachment att,
    PostaMessage msg, {
    PostaQuickFile? quick,
  }) onFile;
  final Future<void> Function(
    PostaMessage msg, {
    PostaQuickFile? quick,
  }) onFileAll;
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
            if (isPostaNoiseMail(from: msg.fromAddress, subject: msg.subject))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: AppCard(
                  stripe: AppTheme.pencil,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('posta.noiseHint'.tr()),
                  ),
                ),
              )
            else if (!msg.assigned) ...[
              const SizedBox(height: 12),
              _PostaSuggestCard(
                messageId: messageId,
                busy: busy,
                onConfirm: onAssignHit,
              ),
              _PostaQuickFileBar(
                messageId: messageId,
                busy: busy,
                msg: msg,
                onFile: onFile,
                onFileAll: onFileAll,
              ),
            ] else
              _PostaQuickFileBar(
                messageId: messageId,
                busy: busy,
                msg: msg,
                onFile: onFile,
                onFileAll: onFileAll,
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isPostaNoiseMail(from: msg.fromAddress, subject: msg.subject))
                  FilledButton(
                    onPressed: busy ? null : onIgnore,
                    child: Text('posta.ignore'.tr()),
                  )
                else ...[
                  FilledButton(
                    onPressed: busy ? null : onAssign,
                    child: Text('posta.assign'.tr()),
                  ),
                  if (msg.assigned)
                    FilledButton.tonal(
                      onPressed: busy ? null : () => onReply(msg),
                      child: Text('posta.reply'.tr()),
                    ),
                  if (msg.assigned && !msg.isDone)
                    FilledButton.tonal(
                      onPressed: busy ? null : onDone,
                      child: Text('posta.markDone'.tr()),
                    ),
                  if (msg.isDone)
                    OutlinedButton(
                      onPressed: busy ? null : onUndone,
                      child: Text('posta.undone'.tr()),
                    ),
                  if (msg.unfiledCount > 1)
                    FilledButton.tonal(
                      onPressed: busy ? null : () => onFileAll(msg),
                      child: Text(
                        'posta.fileAll'.tr(
                          namedArgs: {'count': '${msg.unfiledCount}'},
                        ),
                      ),
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
                ],
                if (msg.openInGmail != null)
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse(msg.openInGmail!)),
                    child: Text('posta.openGmail'.tr()),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            _PostaThreadPane(messageId: messageId),
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'posta.preview'.tr(),
                        icon: const Icon(Icons.visibility_outlined),
                        onPressed: () => _previewPostaAttachment(context, att),
                      ),
                      if (!att.filed)
                        FilledButton(
                          onPressed: busy ? null : () => onFile(att, msg),
                          child: Text('posta.file'.tr()),
                        ),
                    ],
                  ),
                ),
            const SizedBox(height: 24),
            PostaHtmlBody(html: msg.bodyHtml, text: msg.bodyText),
          ],
        );
      },
    );
  }
}

Future<void> _previewPostaAttachment(
  BuildContext context,
  PostaAttachment att,
) async {
  try {
    final url = await signedPostaUrl(att.storagePath);
    await launchUrl(Uri.parse(url));
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('folder.openError'.tr())),
      );
    }
  }
}

/// Jedno tlačítko, když je jasný klient i blok. Gestor pořád potvrzuje klikem.
class _PostaQuickFileBar extends ConsumerWidget {
  const _PostaQuickFileBar({
    required this.messageId,
    required this.busy,
    required this.msg,
    required this.onFile,
    required this.onFileAll,
  });

  final String messageId;
  final bool busy;
  final PostaMessage msg;
  final Future<void> Function(
    PostaAttachment att,
    PostaMessage msg, {
    PostaQuickFile? quick,
  }) onFile;
  final Future<void> Function(
    PostaMessage msg, {
    PostaQuickFile? quick,
  }) onFileAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(postaQuickFileProvider(messageId));
    return async.maybeWhen(
      data: (quick) {
        if (quick == null) return const SizedBox.shrink();
        final block = quick.target.labelKey.tr();
        final place = quick.target.place;
        final where = place == null || place.isEmpty ? block : '$block · $place';
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              onPressed: busy
                  ? null
                  : () => quick.count > 1
                      ? onFileAll(msg, quick: quick)
                      : onFile(quick.attachment, msg, quick: quick),
              child: Text(
                (quick.count > 1
                        ? 'posta.fileAllTo'
                        : 'posta.quickFile')
                    .tr(
                  namedArgs: {
                    'name': quick.clienteNombre,
                    'block': where,
                    'count': '${quick.count}',
                  },
                ),
              ),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _PostaBounceStrip extends ConsumerWidget {
  const _PostaBounceStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(postaBounceListProvider).valueOrNull ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'posta.badgeBounce'.tr(namedArgs: {'count': '${rows.length}'}),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppTheme.statusAlert,
                ),
          ),
          const SizedBox(height: 8),
          for (final row in rows.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                stripe: AppTheme.statusAlert,
                onTap: row.clienteId.isEmpty
                    ? null
                    : () => context.go('/clientes/${row.clienteId}'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.clienteNombre,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        [
                          'posta.bounce'.tr(),
                          if (row.subject.isNotEmpty) row.subject,
                          if ((row.reason ?? '').isNotEmpty) row.reason!,
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
      ),
    );
  }
}

class _PostaThreadPane extends ConsumerWidget {
  const _PostaThreadPane({required this.messageId});

  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(postaThreadProvider(messageId));
    return async.maybeWhen(
      data: (rows) {
        if (rows.length < 2) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'posta.thread'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  emphasized: row.current,
                  stripe: row.bounced
                      ? AppTheme.statusAlert
                      : (row.inbound ? AppTheme.accent : AppTheme.rule),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            row.inbound
                                ? 'posta.directionIn'.tr()
                                : 'posta.directionOut'.tr(),
                            if (row.subject.isNotEmpty) row.subject,
                            if (row.bounced) 'posta.bounce'.tr(),
                          ].join(' · '),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if ((row.body ?? '').trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              row.body!.trim(),
                              maxLines: row.current ? 8 : 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
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
  const _PostaClienteDialog({this.suggested});

  final PostaClienteHit? suggested;

  @override
  ConsumerState<_PostaClienteDialog> createState() =>
      _PostaClienteDialogState();
}

class _PostaClienteDialogState extends ConsumerState<_PostaClienteDialog> {
  final _q = TextEditingController();
  late List<PostaClienteHit> _hits;
  var _loading = false;

  @override
  void initState() {
    super.initState();
    final s = widget.suggested;
    _hits = s == null ? const [] : [s];
  }

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
                      selected: widget.suggested?.id == hit.id,
                      title: Text(hit.nombre),
                      subtitle: () {
                        final sub = [
                          if (hit.matchMethod != null)
                            'posta.match.${hit.matchMethod}'.tr(),
                          if (hit.subtitle.isNotEmpty) hit.subtitle,
                        ].join(' ').trim();
                        return sub.isEmpty ? null : Text(sub);
                      }(),
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView(
            shrinkWrap: true,
            children: [
              if (targets.any((t) => t.suggested))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'posta.fileHint'.tr(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              for (final t in targets)
                ListTile(
                  selected: t.suggested,
                  title: Text(t.labelKey.tr()),
                  subtitle: t.place == null && !t.suggested
                      ? null
                      : Text(
                          [
                            if (t.suggested) 'posta.fileSuggest'.tr(),
                            if (t.place != null) t.place!,
                          ].join(' · '),
                        ),
                  onTap: () => Navigator.pop(context, t),
                ),
            ],
          ),
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
