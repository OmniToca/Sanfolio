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
import 'office_citas.dart';
import 'office_citas_providers.dart';

/// Policie / magistrát / NIE / notář v jednom dni. Nic se samo neodešle.
class OfficeCitasScreen extends ConsumerWidget {
  const OfficeCitasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(citasListProvider);
    final on = ref.watch(citasOnProvider);
    final when = DateFormat.yMMMMEEEEd(context.locale.toString()).format(on);
    return Scaffold(
      appBar: AppBar(
        title: Text('citas.title'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/inbox'),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('citas.loadError'.tr())),
        data: (rows) {
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
                        title: 'citas.title'.tr(),
                        subtitle: 'citas.hint'.tr(),
                        actions: [
                          OutlinedButton.icon(
                            onPressed: () => _pickDay(context, ref, on),
                            icon: const Icon(Icons.event, size: 18),
                            label: Text(when),
                          ),
                        ],
                      ),
                      if (rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 48),
                          child: Text('citas.empty'.tr()),
                        )
                      else
                        for (final row in rows)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _CitaCard(row: row),
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

  Future<void> _pickDay(
    BuildContext context,
    WidgetRef ref,
    DateTime on,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: on,
      firstDate: DateTime(on.year - 2),
      lastDate: DateTime(on.year + 2),
    );
    if (picked == null) return;
    ref.read(citasOnProvider.notifier).state = DateTime(
      picked.year,
      picked.month,
      picked.day,
    );
  }
}

class _CitaCard extends StatelessWidget {
  const _CitaCard({required this.row});

  final OfficeCitaRow row;

  @override
  Widget build(BuildContext context) {
    final name = row.clienteNombre.isEmpty
        ? 'inbox.unnamed'.tr()
        : row.clienteNombre;
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
              ['citas.kind.${row.kind}'.tr(), ?due].join(' · '),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.pencil),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FeatureGate(
                  module: GestoriaModule.messaging,
                  child: FilledButton(
                    onPressed: () {
                      final q = Uri(
                        path: '/clientes/${row.clienteId}/mensaje',
                        queryParameters: {
                          'tpl': 'recordatorio',
                          'bloque': row.bloqueKey,
                          'fecha': row.dueOn,
                          'documento': citaBloqueLabel(row.kind),
                        },
                      );
                      context.go('${q.path}?${q.query}');
                    },
                    child: Text('citas.draft'.tr()),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    if (row.kind == 'escritura') {
                      context.go(
                        carpetaBloqueRoute(
                          row.clienteId,
                          'escritura',
                          expedienteId: row.expedienteId,
                        ),
                      );
                      return;
                    }
                    final exp = row.expedienteId;
                    if (exp != null && exp.isNotEmpty) {
                      context.go('/expedientes/$exp');
                      return;
                    }
                    context.go('/clientes/${row.clienteId}');
                  },
                  child: Text(
                    row.kind == 'escritura'
                        ? 'folder.openBlock'.tr()
                        : 'expedientes.openCard'.tr(),
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
