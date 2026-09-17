import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../../core/time/office_date.dart';
import '../carpeta/carpeta_routes.dart';
import 'office_packs.dart';
import 'office_packs_providers.dart';

/// 210 bez podání a koupě po notáři. Jedna obrazovka, AEAT se nepodává.
class OfficePacksScreen extends ConsumerWidget {
  const OfficePacksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final season = ref.watch(season210ListProvider);
    final notary = ref.watch(afterNotaryListProvider);
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
        children: [
          for (final row in rows) _AfterNotaryCard(row: row),
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
  });

  final String title;
  final String empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
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

String? _fmtDate(BuildContext context, String? raw) {
  final dt = parseOfficeDate(raw ?? '');
  if (dt == null) return raw?.trim().isEmpty == true ? null : raw;
  return DateFormat.yMd(context.locale.toString()).format(dt);
}
