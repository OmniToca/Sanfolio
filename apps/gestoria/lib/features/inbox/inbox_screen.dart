import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text('inbox.title'.tr())),
      body: feed.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('inbox.loadError'.tr())),
        data: (rows) {
          final shown =
              rows.where((r) => matchesInboxFilter(r, _filter)).toList();
          return Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    for (final key in inboxFilterKeys) ...[
                      FilterChip(
                        label: Text(
                          key == 'all'
                              ? 'inbox.filterAll'.tr()
                              : key == 'no_channel'
                                  ? 'inbox.noChannel'.tr()
                                  : 'inbox.kind.$key'.tr(),
                        ),
                        selected: _filter == key,
                        onSelected: (_) => setState(() => _filter = key),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: AppContent(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 48),
                  child: shown.isEmpty
                    ? Center(
                        child: Text(
                          rows.isEmpty
                              ? 'inbox.empty'.tr()
                              : 'inbox.emptyFilter'.tr(),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: shown.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final row = shown[i];
                          final canAsk =
                              row.canPedir(nudgeIntervalDays: nudgeDays);
                          return AppCard(
                            onTap: () => _open(context, row),
                            child: ListTile(
                              title: Text(
                                row.clienteNombre.isEmpty
                                    ? 'inbox.unnamed'.tr()
                                    : row.clienteNombre,
                              ),
                              subtitle: Text(_subtitle(row)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (row.canSnooze)
                                    IconButton(
                                      tooltip: 'inbox.snooze'.tr(),
                                      onPressed: () => _snooze(row),
                                      icon: const Icon(Icons.snooze),
                                    ),
                                  FeatureGate(
                                    module: GestoriaModule.messaging,
                                    child: TextButton(
                                      onPressed: () => _pedir(row, canAsk),
                                      child: Text('inbox.askClient'.tr()),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _subtitle(InboxRow row) {
    final block = (row.plazoNote != null && row.plazoNote!.isNotEmpty)
        ? row.plazoNote!
        : 'blocks.${row.bloqueKey}'.tr();
    final kind = 'inbox.kind.${row.itemKind}'.tr();
    final parts = <String>[kind, block];
    final day = inboxFechaIso(row.dueOn);
    if (day.isNotEmpty) parts.add(day);
    if (!row.hasChannel) parts.add('inbox.noChannel'.tr());
    return parts.join(' · ');
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
