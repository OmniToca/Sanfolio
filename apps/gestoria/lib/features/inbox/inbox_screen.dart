import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../../core/time/office_date.dart';
import '../mensajes/mensaje_templates.dart';
import '../settings/office_settings_controller.dart';
import 'inbox_providers.dart';

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  var _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(inboxFeedProvider);
    final nudgeDays =
        ref.watch(officeSettingsProvider).valueOrNull?.nudgeIntervalDays ?? 7;
    final office =
        ref.watch(officeSettingsProvider).valueOrNull?.displayName ?? '';
    return Scaffold(
      body: feed.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('inbox.loadError'.tr())),
        data: (rows) {
          final shown =
              rows.where((r) => matchesInboxFilter(r, _filter)).toList();
          final when = DateFormat.MMMMEEEEd(context.locale.toString());
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppTheme.contentWide,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppPageHeader(
                        kicker: office.isEmpty ? when.format(DateTime.now()) : office,
                        title: 'inbox.title'.tr(),
                        subtitle: 'inbox.onDesk'.tr(
                          namedArgs: {'count': '${shown.length}'},
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final key in inboxFilterKeys)
                            AppStamp(
                              label: key == 'all'
                                  ? 'inbox.filterAll'.tr()
                                  : key == 'no_channel'
                                      ? 'inbox.noChannel'.tr()
                                      : 'inbox.kind.$key'.tr(),
                              selected: _filter == key,
                              onTap: () => setState(() => _filter = key),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (shown.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 48),
                          child: Text(
                            rows.isEmpty
                                ? 'inbox.empty'.tr()
                                : 'inbox.emptyFilter'.tr(),
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: AppTheme.pencil,
                                ),
                          ),
                        )
                      else
                        for (final row in shown)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _InboxSheet(
                              row: row,
                              onOpen: () => _open(context, row),
                              onSnooze: row.canSnooze ? () => _snooze(row) : null,
                              onAsk: () => _pedir(
                                row,
                                row.canPedir(nudgeIntervalDays: nudgeDays),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _snooze(InboxRow row) async {
    final plazoId = row.plazoId;
    if (plazoId == null || plazoId.isEmpty) return;
    final today = calendarDay(DateTime.now());
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) {
        final tomorrow = today.add(const Duration(days: 1));
        return AlertDialog(
          title: Text('inbox.snooze'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('inbox.snoozeHint'.tr()),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(ctx, tomorrow),
                child: Text('inbox.snooze1'.tr()),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, today.add(const Duration(days: 3))),
                child: Text('inbox.snooze3'.tr()),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, today.add(const Duration(days: 7))),
                child: Text('inbox.snooze7'.tr()),
              ),
              TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: tomorrow,
                    firstDate: tomorrow,
                    lastDate: today.add(const Duration(days: 365)),
                  );
                  if (d == null || !ctx.mounted) return;
                  Navigator.pop(ctx, calendarDay(d));
                },
                child: Text('inbox.snoozePick'.tr()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('clients.cancel'.tr()),
            ),
          ],
        );
      },
    );
    if (picked == null || !mounted) return;
    try {
      await snoozePlazo(plazoId: plazoId, until: picked);
      ref.invalidate(inboxFeedProvider);
      if (!mounted) return;
      _toast('inbox.snoozed'.tr());
    } on Object {
      if (!mounted) return;
      _toast('inbox.snoozeError'.tr());
    }
  }

  Future<void> _pedir(InboxRow row, bool canAsk) async {
    if (!row.hasChannel) {
      _toast('inbox.noChannel'.tr());
      return;
    }
    if (!canAsk) {
      _toast('inbox.askedRecently'.tr());
      return;
    }
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    if (tenantId == null) {
      _toast('inbox.askError'.tr());
      return;
    }
    final despacho =
        ref.read(officeSettingsProvider).valueOrNull?.displayName ?? '';
    try {
      await pedirAlCliente(
        tenantId: tenantId,
        row: row,
        despacho: despacho.isEmpty ? '—' : despacho,
      );
      ref.invalidate(inboxFeedProvider);
    } on Object {
      if (!mounted) return;
      _toast('inbox.askError'.tr());
      return;
    }
    if (!mounted) return;
    final tpl = templateKeyForInboxKind(row.itemKind);
    final fecha = inboxFechaIso(row.dueOn);
    final q = <String, String>{
      'tpl': tpl,
      'bloque': row.bloqueKey,
      if (fecha.isNotEmpty) 'fecha': fecha,
    };
    context.go(
      Uri(
        path: '/clientes/${row.clienteId}/mensaje',
        queryParameters: q,
      ).toString(),
    );
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _open(BuildContext context, InboxRow row) {
    final tipo = row.expedienteTipo ?? '';
    final expId = row.expedienteId;
    if (expId != null &&
        expId.isNotEmpty &&
        tipo.isNotEmpty &&
        tipo != 'compraventa') {
      context.go('/expedientes/$expId');
      return;
    }
    context.go('/clientes/${row.clienteId}/carpeta');
  }
}

Color _inboxStripe(String kind) {
  switch (kind) {
    case 'overdue':
      return AppTheme.urgent;
    case 'due_today':
      return AppTheme.statusWarn;
    case 'missing_document':
      return AppTheme.statusAlert;
    case 'missing_data':
      return AppTheme.statusWarn;
    case 'stale_expediente':
      return AppTheme.pencil;
    default:
      return AppTheme.statusWatch;
  }
}

class _InboxSheet extends StatelessWidget {
  const _InboxSheet({
    required this.row,
    required this.onOpen,
    required this.onAsk,
    this.onSnooze,
  });

  final InboxRow row;
  final VoidCallback onOpen;
  final VoidCallback onAsk;
  final VoidCallback? onSnooze;

  @override
  Widget build(BuildContext context) {
    final name = row.clienteNombre.isEmpty
        ? 'inbox.unnamed'.tr()
        : row.clienteNombre;
    final block = (row.plazoNote != null && row.plazoNote!.isNotEmpty)
        ? row.plazoNote!
        : 'blocks.${row.bloqueKey}'.tr();
    final due = row.dueOn == null
        ? null
        : DateFormat.yMMMd(context.locale.toString()).format(row.dueOn!);
    return AppCard(
      stripe: _inboxStripe(row.itemKind),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      'inbox.kind.${row.itemKind}'.tr(),
                      block,
                      if (due != null) due,
                      if (!row.hasChannel) 'inbox.noChannel'.tr(),
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (onSnooze != null)
              IconButton(
                tooltip: 'inbox.snooze'.tr(),
                onPressed: onSnooze,
                icon: const Icon(Icons.snooze_outlined),
              ),
            FeatureGate(
              module: GestoriaModule.messaging,
              child: TextButton(
                onPressed: onAsk,
                child: Text('inbox.askClient'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
