import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../clientes/cliente_card_widgets.dart';
import 'posta_providers.dart';

/// Slot `cliente.tabs`: přijaté maily přiřazené ke kartě.
class ClientePostaSection extends ConsumerWidget {
  const ClientePostaSection({super.key, required this.clienteId});

  final String clienteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clientePostaProvider(clienteId));
    return FeatureGate(
      module: GestoriaModule.messaging,
      child: ClienteCardSection(
        title: 'posta.cardTitle'.tr(),
        hint: 'posta.cardHint'.tr(),
        trailing: TextButton(
          onPressed: () => context.go('/posta'),
          child: Text('posta.openInbox'.tr()),
        ),
        child: async.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, st) => Text('posta.loadError'.tr()),
          data: (rows) {
            if (rows.isEmpty) {
              return Text(
                'posta.cardEmpty'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.pencil,
                    ),
              );
            }
            return PreviewThenHistory(
              itemCount: rows.length,
              expandLabel: 'common.history'.tr(),
              collapseLabel: 'common.historyHide'.tr(),
              builder: (context, i) {
                final row = rows[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    row.subject?.isNotEmpty == true
                        ? row.subject!
                        : 'posta.noSubject'.tr(),
                  ),
                  subtitle: Text(
                    [
                      row.fromLabel,
                      DateFormat.yMMMd(context.locale.toString())
                          .add_Hm()
                          .format(row.receivedAt.toLocal()),
                      if (row.hasAttachments)
                        'posta.attachCount'.tr(
                          namedArgs: {'count': '${row.attachments.length}'},
                        ),
                    ].join(' · '),
                  ),
                  onTap: () => context.go('/posta/${row.id}'),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
