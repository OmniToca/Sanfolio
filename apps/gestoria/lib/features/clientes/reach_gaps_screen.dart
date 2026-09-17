import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import 'reach_gaps.dart';
import 'reach_gaps_providers.dart';

/// Karty, na které Pedir ani portál nedosáhnou. Doplnění z kontaktu, ne odeslání.
class ReachGapsScreen extends ConsumerWidget {
  const ReachGapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reachGapsListProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('clients.reachTitle'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/inbox'),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('clients.reachLoadError'.tr())),
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
                        title: 'clients.reachTitle'.tr(),
                        subtitle: 'clients.reachHint'.tr(),
                      ),
                      if (rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 48),
                          child: Text('clients.reachEmpty'.tr()),
                        )
                      else
                        for (final row in rows)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _ReachCard(row: row),
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

class _ReachCard extends ConsumerStatefulWidget {
  const _ReachCard({required this.row});

  final ReachGapRow row;

  @override
  ConsumerState<_ReachCard> createState() => _ReachCardState();
}

class _ReachCardState extends ConsumerState<_ReachCard> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final name =
        row.clienteNombre.isEmpty ? 'inbox.unnamed'.tr() : row.clienteNombre;
    final bits = <String>[
      if (row.gap.sinCanal) 'clients.reachSinCanal'.tr(),
      if (row.gap.contactOnly) 'clients.reachContactOnly'.tr(),
      if (row.gap.noLocale) 'clients.reachNoLocale'.tr(),
      if ((row.contactNombre ?? '').isNotEmpty) row.contactNombre!,
    ];
    return AppCard(
      stripe: row.gap.sinCanal ? AppTheme.statusAlert : AppTheme.statusWarn,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              bits.join(' · '),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.pencil,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (row.gap.canCopy)
                  FilledButton(
                    onPressed: _busy ? null : _copy,
                    child: Text('clients.reachCopy'.tr()),
                  ),
                TextButton(
                  onPressed: () => context.go('/clientes/${row.clienteId}'),
                  child: Text('clients.openFolder'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy() async {
    setState(() => _busy = true);
    try {
      final copied = await copyChannelFromContact(widget.row.clienteId);
      if (!mounted) return;
      ref.invalidate(reachGapsListProvider);
      ref.invalidate(reachGapsCountProvider);
      if (!copied.email && !copied.tel && !copied.locale) {
        _toast('clients.reachCopyNone'.tr());
        return;
      }
      _toast('clients.reachCopied'.tr());
    } on Object {
      if (mounted) _toast('clients.reachCopyError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
