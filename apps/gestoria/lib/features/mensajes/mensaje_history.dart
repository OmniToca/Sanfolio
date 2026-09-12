import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
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
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'messages.history'.tr(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              feed.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, st) => Text('messages.historyError'.tr()),
                data: (rows) {
                  if (rows.isEmpty) {
                    return Text(
                      'messages.historyEmpty'.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.pencil,
                          ),
                    );
                  }
                  return Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        _MensajeTile(
                          mensaje: rows[i],
                          clientLocale: clientLocale,
                          onDiscard: () => _discard(context, ref, rows[i]),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
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

class _MensajeTile extends StatelessWidget {
  const _MensajeTile({
    required this.mensaje,
    required this.clientLocale,
    required this.onDiscard,
  });

  final ClienteMensaje mensaje;
  final String clientLocale;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceMuted,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    mensaje.asunto?.isNotEmpty == true
                        ? mensaje.asunto!
                        : 'messages.title'.tr(),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  'messages.status.${mensaje.status}'.tr(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.pencil,
                      ),
                ),
                if (mensaje.status == 'draft')
                  IconButton(
                    tooltip: 'messages.discard'.tr(),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDiscard,
                  ),
              ],
            ),
            Text(
              'messages.original'.tr(
                namedArgs: {'locale': mensaje.localeOriginal},
              ),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.pencil,
                  ),
            ),
            Text(mensaje.cuerpo),
            if (mensaje.translationBesideOriginal(clientLocale)
                case final tr?) ...[
              const SizedBox(height: 8),
              Text(
                'messages.translation'.tr(
                  namedArgs: {'locale': clientLocale},
                ),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.pencil,
                    ),
              ),
              Text(tr),
            ],
          ],
        ),
      ),
    );
  }
}
