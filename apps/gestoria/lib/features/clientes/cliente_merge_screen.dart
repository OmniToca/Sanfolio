import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/staff_role.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import 'cliente_merge.dart';
import 'clientes_providers.dart';

final duplicatePairsProvider = FutureProvider<List<DuplicatePair>>((ref) async {
  ref.watch(authControllerProvider);
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return const [];
  final rows = await client.rpc(
    'suggest_cliente_duplicates',
    params: {'p_tenant_id': tenantId},
  );
  final out = <DuplicatePair>[];
  if (rows is! List) return out;
  for (final raw in rows) {
    if (raw is! Map) continue;
    final row = duplicatePairFromRpc(Map<String, dynamic>.from(raw));
    if (row != null) out.add(row);
  }
  return out;
});

/// Návrhy po CSV. Sloučení schová druhou kartu, nic se nemaže natvrdo.
class ClienteMergeScreen extends ConsumerWidget {
  const ClienteMergeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(duplicatePairsProvider);
    final canMerge = canMergeClientes(
      ref.watch(authControllerProvider).valueOrNull ?? AuthSnapshot.signedOut,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('clients.mergeTitle'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/clientes'),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('clients.mergeLoadError'.tr())),
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
                        title: 'clients.mergeTitle'.tr(),
                        subtitle: 'clients.mergeHint'.tr(),
                      ),
                      if (!canMerge)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text('clients.mergeForbidden'.tr()),
                        ),
                      if (rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 48),
                          child: Text('clients.mergeEmpty'.tr()),
                        )
                      else
                        for (final row in rows)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _DupCard(row: row, canMerge: canMerge),
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
}

class _DupCard extends ConsumerStatefulWidget {
  const _DupCard({required this.row, required this.canMerge});

  final DuplicatePair row;
  final bool canMerge;

  @override
  ConsumerState<_DupCard> createState() => _DupCardState();
}

class _DupCardState extends ConsumerState<_DupCard> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return AppCard(
      stripe: AppTheme.statusWarn,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'clients.mergePair'.tr(
                namedArgs: {
                  'keep': row.keepNombre.isEmpty
                      ? 'inbox.unnamed'.tr()
                      : row.keepNombre,
                  'drop': row.dropNombre.isEmpty
                      ? 'inbox.unnamed'.tr()
                      : row.dropNombre,
                },
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'clients.mergeReason.${row.reason}'.tr(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.pencil,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.canMerge)
                  FilledButton(
                    onPressed: _busy ? null : _merge,
                    child: Text('clients.mergeRun'.tr()),
                  ),
                TextButton(
                  onPressed: () => context.go('/clientes/${row.keepId}'),
                  child: Text('clients.mergeOpenKeep'.tr()),
                ),
                TextButton(
                  onPressed: () => context.go('/clientes/${row.dropId}'),
                  child: Text('clients.mergeOpenDrop'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _merge() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('clients.mergeRun'.tr()),
        content: Text('clients.mergeConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('clients.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('clients.mergeRun'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final client = trySupabaseClient();
      if (client == null) throw StateError('not configured');
      await client.rpc(
        'merge_clientes',
        params: {
          'p_keep_id': widget.row.keepId,
          'p_drop_id': widget.row.dropId,
        },
      );
      if (!mounted) return;
      ref.invalidate(duplicatePairsProvider);
      ref.invalidate(clientesListProvider);
      _toast('clients.mergeDone'.tr());
    } on Object catch (e) {
      if (!mounted) return;
      final s = '$e'.toLowerCase();
      if (s.contains('nie_conflict') || s.contains('23505')) {
        _toast('clients.mergeNieConflict'.tr());
      } else if (s.contains('forbidden') || s.contains('42501')) {
        _toast('clients.mergeForbidden'.tr());
      } else {
        _toast('clients.mergeError'.tr());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
