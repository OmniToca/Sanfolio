import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import 'mensaje_providers.dart';

/// Originál + překlad. Zahodit jen draft, stav `discarded`.
class ClienteMensajeHistory extends ConsumerWidget {
  const ClienteMensajeHistory({
    super.key,
    required this.clienteId,
    required this.clientLocale,
  });

  final String clienteId;
  final String clientLocale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(clienteMensajesProvider(clienteId));
    return FeatureGate(
      module: GestoriaModule.messaging,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'messages.history'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          feed.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, st) => Text('messages.historyError'.tr()),
            data: (rows) {
              if (rows.isEmpty) {
                return Text('messages.historyEmpty'.tr());
              }
              return Column(
                children: [
                  for (final m in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      m.asunto?.isNotEmpty == true
                                          ? m.asunto!
                                          : 'messages.title'.tr(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                  ),
                                  Text('messages.status.${m.status}'.tr()),
                                  if (m.status == 'draft')
                                    IconButton(
                                      tooltip: 'messages.discard'.tr(),
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _discard(context, ref, m),
                                    ),
                                ],
                              ),
                              Text(
                                'messages.original'.tr(
                                  namedArgs: {'locale': m.localeOriginal},
                                ),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              Text(m.cuerpo),
                              if (m.translationBesideOriginal(clientLocale)
                                  case final tr?) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'messages.translation'.tr(
                                    namedArgs: {'locale': clientLocale},
                                  ),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                Text(tr),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _discard(
    BuildContext context,
    WidgetRef ref,
    ClienteMensaje m,
  ) async {
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    if (tenantId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('messages.discard'.tr()),
        content: Text('messages.discardConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('clients.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('messages.discard'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await discardMensaje(tenantId: tenantId, mensajeId: m.id);
      ref.invalidate(clienteMensajesProvider(clienteId));
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('messages.discardError'.tr())),
      );
    }
  }
}
