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
import '../carpeta/carpeta_routes.dart';
import '../inbox/inbox_providers.dart';
import '../settings/office_settings_controller.dart';
import 'office_pack_pedir.dart';
import 'office_packs.dart';
import 'office_packs_providers.dart';
import 'expiring_campaign.dart';

/// 210, po notáři a expirace dokladů. Jedna obrazovka, nic se samo neodešle.
class OfficePacksScreen extends ConsumerWidget {
  const OfficePacksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final season = ref.watch(season210ListProvider);
    final notary = ref.watch(afterNotaryListProvider);
    final ibi = ref.watch(seasonIbiListProvider);
    final expiry = ref.watch(expiringListProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('packs.campaignTitle'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/inbox'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppTheme.contentWide),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppPageHeader(
                    title: 'packs.campaignTitle'.tr(),
                    subtitle: 'packs.campaignHint'.tr(),
                  ),
                  FeatureGate(
                    module: GestoriaModule.impuestos,
                    child: _SeasonBlock(async: season),
                  ),
                  FeatureGate(
                    module: GestoriaModule.carpetaInmueble,
                    child: _NotaryBlock(async: notary),
                  ),
                  FeatureGate(
                    module: GestoriaModule.carpetaInmueble,
                    child: _IbiBlock(async: ibi),
                  ),
                  _ExpiryBlock(async: expiry),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeasonBlock extends StatelessWidget {
  const _SeasonBlock({required this.async});

  final AsyncValue<List<Season210Row>> async;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text('packs.seasonLoadError'.tr()),
      ),
      data: (rows) => _PackSection(
        title: 'packs.seasonTitle'.tr(),
        empty: 'packs.seasonEmpty'.tr(),
        trailing: rows.isEmpty
            ? null
            : _PackBulkPedirButton(
                loadRequests: () => season210PedirRequests(
                  rows,
                  documentoLabel: (row) {
                    final missing = [
                      for (final t in row.missingDocs) 'docs.$t'.tr(),
                    ];
                    if (missing.isEmpty) {
                      return row.periodo ?? 'modelo 210';
                    }
                    return missing.join(', ');
                  },
                ),
              ),
        children: [
          for (final row in rows) _Season210Card(row: row),
        ],
      ),
    );
  }
}

class _NotaryBlock extends StatelessWidget {
  const _NotaryBlock({required this.async});

  final AsyncValue<List<AfterNotaryRow>> async;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text('packs.notaryLoadError'.tr()),
      ),
      data: (rows) => _PackSection(
        title: 'packs.notaryTitle'.tr(),
        empty: 'packs.notaryEmpty'.tr(),
        trailing: rows.isEmpty
            ? null
            : _PackBulkPedirButton(
                loadRequests: () => afterNotaryPedirRequests(rows),
              ),
        children: [
          for (final row in rows) _AfterNotaryCard(row: row),
        ],
      ),
    );
  }
}

class _IbiBlock extends StatelessWidget {
  const _IbiBlock({required this.async});

  final AsyncValue<List<Season210Row>> async;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text('packs.ibiLoadError'.tr()),
      ),
      data: (rows) => _PackSection(
        title: 'packs.ibiTitle'.tr(),
        empty: 'packs.ibiEmpty'.tr(),
        trailing: rows.isEmpty
            ? null
            : _PackBulkPedirButton(
                loadRequests: () => seasonIbiPedirRequests(
                  rows,
                  documentoLabel: (row) {
                    final missing = [
                      for (final t in row.missingDocs) 'docs.$t'.tr(),
                    ];
                    if (missing.isEmpty) {
                      return row.periodo ?? 'IBI';
                    }
                    return missing.join(', ');
                  },
                ),
              ),
        children: [
          for (final row in rows) _IbiCard(row: row),
        ],
      ),
    );
  }
}

class _IbiCard extends StatelessWidget {
  const _IbiCard({required this.row});

  final Season210Row row;

  @override
  Widget build(BuildContext context) {
    final name = row.clienteNombre.isEmpty
        ? 'inbox.unnamed'.tr()
        : row.clienteNombre;
    final missing = [
      for (final t in row.missingDocs) 'docs.$t'.tr(),
    ];
    final due = _fmtDate(context, row.dueOn);
    return AppCard(
      stripe: AppTheme.statusWarn,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              [
                if (row.periodo != null)
                  'packs.ibiPeriod'.tr(
                    namedArgs: {'period': row.periodo!},
                  ),
                if (due != null)
                  'packs.seasonDue'.tr(namedArgs: {'date': due})
                else
                  'packs.seasonNoDue'.tr(),
              ].join(' · '),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.pencil,
                  ),
            ),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'packs.seasonMissing'.tr(
                  namedArgs: {'docs': missing.join(', ')},
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () {
                    final q = Uri(
                      path: '/clientes/${row.clienteId}/mensaje',
                      queryParameters: {
                        'tpl': missing.isEmpty
                            ? 'recordatorio'
                            : 'falta_documento',
                        'bloque': 'suma',
                        'fecha': ?due,
                        'documento': missing.isEmpty
                            ? (row.periodo ?? 'IBI')
                            : missing.join(', '),
                      },
                    );
                    context.go('${q.path}?${q.query}');
                  },
                  child: Text('packs.draftIbi'.tr()),
                ),
                TextButton(
                  onPressed: () => context.go(
                    carpetaBloqueRoute(
                      row.clienteId,
                      'suma',
                      expedienteId: row.expedienteId,
                    ),
                  ),
                  child: Text('folder.openBlock'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpiryBlock extends StatelessWidget {
  const _ExpiryBlock({required this.async});

  final AsyncValue<List<ExpiringRow>> async;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text('packs.expiryLoadError'.tr()),
      ),
      data: (rows) => _PackSection(
        title: 'packs.expiryTitle'.tr(),
        empty: 'packs.expiryEmpty'.tr(),
        trailing: rows.isEmpty
            ? null
            : _PackBulkPedirButton(
                loadRequests: () => expiringPedirRequests(rows),
              ),
        children: [
          for (final row in rows) _ExpiringCard(row: row),
        ],
      ),
    );
  }
}

class _PackSection extends StatelessWidget {
  const _PackSection({
    required this.title,
    required this.empty,
    required this.children,
    this.trailing,
  });

  final String title;
  final String empty;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          if (children.isEmpty)
            Text(empty)
          else
            for (final child in children)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: child,
              ),
        ],
      ),
    );
  }
}

class _Season210Card extends StatelessWidget {
  const _Season210Card({required this.row});

  final Season210Row row;

  @override
  Widget build(BuildContext context) {
    final name = row.clienteNombre.isEmpty
        ? 'inbox.unnamed'.tr()
        : row.clienteNombre;
    final missing = [
      for (final t in row.missingDocs) 'docs.$t'.tr(),
    ];
    final due = _fmtDate(context, row.dueOn);
    return AppCard(
      stripe: AppTheme.statusWarn,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              [
                if (row.periodo != null)
                  'packs.seasonPeriod'.tr(
                    namedArgs: {'period': row.periodo!},
                  ),
                if (due != null)
                  'packs.seasonDue'.tr(namedArgs: {'date': due})
                else
                  'packs.seasonNoDue'.tr(),
              ].join(' · '),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.pencil,
                  ),
            ),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'packs.seasonMissing'.tr(
                  namedArgs: {'docs': missing.join(', ')},
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () {
                    final q = Uri(
                      path: '/clientes/${row.clienteId}/mensaje',
                      queryParameters: {
                        'tpl': missing.isEmpty
                            ? 'recordatorio'
                            : 'falta_documento',
                        'bloque': 'modelo_210',
                        'fecha': ?due,
                        'documento': missing.isEmpty
                            ? (row.periodo ?? 'modelo 210')
                            : missing.join(', '),
                      },
                    );
                    context.go('${q.path}?${q.query}');
                  },
                  child: Text('packs.draft210'.tr()),
                ),
                TextButton(
                  onPressed: () =>
                      context.go('/expedientes/${row.expedienteId}'),
                  child: Text('packs.open210'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AfterNotaryCard extends StatelessWidget {
  const _AfterNotaryCard({required this.row});

  final AfterNotaryRow row;

  @override
  Widget build(BuildContext context) {
    final name = row.clienteNombre.isEmpty
        ? 'inbox.unnamed'.tr()
        : row.clienteNombre;
    final fecha = _fmtDate(context, row.escrituraFecha);
    final supply = firstSupplyTask(row.tasks);
    return AppCard(
      stripe: AppTheme.statusWarn,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              [
                if (fecha != null)
                  'packs.notaryEscritura'.tr(namedArgs: {'date': fecha}),
                if ((row.direccion ?? '').isNotEmpty) row.direccion!,
              ].join(' · '),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.pencil,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in row.tasks)
                  Chip(label: Text('packs.task.$t'.tr())),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () {
                    final bloque = draftBloqueForNotary(row.tasks);
                    final addr = (row.direccion ?? '').trim();
                    final q = Uri(
                      path: '/clientes/${row.clienteId}/mensaje',
                      queryParameters: {
                        'tpl': draftTemplateForNotary(row.tasks),
                        'bloque': bloque,
                        'fecha': ?fecha,
                        'inmueble': ?(addr.isEmpty ? null : addr),
                      },
                    );
                    context.go('${q.path}?${q.query}');
                  },
                  child: Text(
                    supply != null
                        ? 'packs.draftTitular'.tr()
                        : 'packs.draft210'.tr(),
                  ),
                ),
                if (row.tasks.contains('plusvalia'))
                  TextButton(
                    onPressed: () => context.go(
                      carpetaBloqueRoute(
                        row.clienteId,
                        'plusvalia',
                        expedienteId: row.expedienteId,
                      ),
                    ),
                    child: Text('packs.task.plusvalia'.tr()),
                  ),
                if (row.tasks.contains('modelo_210'))
                  TextButton(
                    onPressed: () {
                      final tax = row.taxExpedienteId;
                      if (tax != null) {
                        context.go('/expedientes/$tax');
                      } else {
                        context.go('/clientes/${row.clienteId}');
                      }
                    },
                    child: Text('packs.open210'.tr()),
                  ),
                TextButton(
                  onPressed: () => context.go(
                    carpetaRoute(
                      row.clienteId,
                      expedienteId: row.expedienteId,
                    ),
                  ),
                  child: Text('expedientes.openFolder'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpiringCard extends StatelessWidget {
  const _ExpiringCard({required this.row});

  final ExpiringRow row;

  @override
  Widget build(BuildContext context) {
    final name = row.clienteNombre.isEmpty
        ? 'inbox.unnamed'.tr()
        : row.clienteNombre;
    final due = _fmtDate(context, row.expiresOn);
    return AppCard(
      stripe: row.isExpired ? AppTheme.statusAlert : AppTheme.statusWarn,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              [
                'packs.expiryKind.${row.kind}'.tr(),
                row.isExpired
                    ? 'clients.docExpired'.tr()
                    : 'clients.docExpiring'.tr(),
                if (due != null)
                  'packs.expiryDue'.tr(namedArgs: {'date': due}),
              ].join(' · '),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.pencil,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () {
                    final q = Uri(
                      path: '/clientes/${row.clienteId}/mensaje',
                      queryParameters: {
                        'tpl': row.isExpired ? 'vencido' : 'recordatorio',
                        'bloque': row.kind,
                        'fecha': row.expiresOn,
                        'documento': expiringBloqueLabel(row.kind),
                      },
                    );
                    context.go('${q.path}?${q.query}');
                  },
                  child: Text('packs.draftExpiry'.tr()),
                ),
                TextButton(
                  onPressed: () {
                    if (row.kind == 'poder' || row.kind == 'seguro') {
                      context.go(
                        carpetaBloqueRoute(
                          row.clienteId,
                          row.kind,
                          expedienteId: row.expedienteId,
                        ),
                      );
                      return;
                    }
                    context.go('/clientes/${row.clienteId}');
                  },
                  child: Text(
                    row.kind == 'poder' || row.kind == 'seguro'
                        ? 'folder.openBlock'.tr()
                        : 'packs.openCard'.tr(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String? _fmtDate(BuildContext context, String? raw) {
  final dt = parseOfficeDate(raw ?? '');
  if (dt == null) return raw?.trim().isEmpty == true ? null : raw;
  return DateFormat.yMd(context.locale.toString()).format(dt);
}

/// Nachystá drafty najednou. Odeslat musí gestor.
class _PackBulkPedirButton extends ConsumerStatefulWidget {
  const _PackBulkPedirButton({required this.loadRequests});

  final Future<List<PedirDraftRequest>> Function() loadRequests;

  @override
  ConsumerState<_PackBulkPedirButton> createState() =>
      _PackBulkPedirButtonState();
}

class _PackBulkPedirButtonState extends ConsumerState<_PackBulkPedirButton> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    return FeatureGate(
      module: GestoriaModule.messaging,
      child: FilledButton.tonalIcon(
        onPressed: _busy ? null : _run,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.outgoing_mail, size: 18),
        label: Text('packs.bulkPedir'.tr()),
      ),
    );
  }

  Future<void> _run() async {
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    if (tenantId == null) {
      _toast('packs.bulkPedirError'.tr());
      return;
    }
    setState(() => _busy = true);
    try {
      final requests = await widget.loadRequests();
      final nudge =
          ref.read(officeSettingsProvider).valueOrNull?.nudgeIntervalDays ?? 7;
      final plan = planPedirDrafts(
        requests,
        nudgeIntervalDays: nudge,
      );
      if (!mounted) return;
      if (plan.toDraft.isEmpty) {
        _toast('packs.bulkPedirNone'.tr());
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('packs.bulkPedir'.tr()),
          content: Text(
            'packs.bulkPedirConfirm'.tr(
              namedArgs: {
                'draft': '${plan.toDraft.length}',
                'noChannel': '${plan.noChannel}',
                'recent': '${plan.askedRecently}',
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('clients.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('packs.bulkPedir'.tr()),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final despacho =
          ref.read(officeSettingsProvider).valueOrNull?.displayName ?? '';
      final result = await writePedirDrafts(
        tenantId: tenantId,
        requests: requests,
        despacho: despacho.isEmpty ? '—' : despacho,
        nudgeIntervalDays: nudge,
      );
      if (!mounted) return;
      ref.invalidate(season210ListProvider);
      ref.invalidate(afterNotaryListProvider);
      ref.invalidate(seasonIbiListProvider);
      ref.invalidate(seasonIbiCountProvider);
      ref.invalidate(expiringListProvider);
      ref.invalidate(expiringCountProvider);
      ref.invalidate(inboxFeedProvider);
      if (result.errors > 0 && result.drafted == 0) {
        _toast('packs.bulkPedirError'.tr());
        return;
      }
      _toast(
        'packs.bulkPedirDone'.tr(
          namedArgs: {
            'draft': '${result.drafted}',
            'noChannel': '${result.noChannel}',
            'recent': '${result.askedRecently}',
          },
        ),
      );
    } on Object {
      if (mounted) _toast('packs.bulkPedirError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

