import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../clientes/cliente_card_widgets.dart';
import 'posta_timeline.dart';

/// Slot `cliente.tabs`: maily od klienta i výzvy kanceláře jemu.
class ClientePostaSection extends ConsumerWidget {
  const ClientePostaSection({super.key, required this.clienteId});

  final String clienteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clienteMailTimelineProvider(clienteId));
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
            final unfiled = rows.fold<int>(
              0,
              (sum, row) => sum + row.unfiledCount,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (unfiled > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'posta.cardUnfiled'.tr(
                        namedArgs: {'count': '$unfiled'},
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.pencil,
                          ),
                    ),
                  ),
                PreviewThenHistory(
                  itemCount: rows.length,
                  expandLabel: 'common.history'.tr(),
                  collapseLabel: 'common.historyHide'.tr(),
                  builder: (context, i) {
                    final row = rows[i];
                    final when = DateFormat.yMMMd(context.locale.toString())
                        .add_Hm()
                        .format(row.at.toLocal());
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        row.inbound
                            ? Icons.call_received
                            : Icons.call_made,
                        color: AppTheme.pencil,
                      ),
                      title: Text(
                        row.subject.isNotEmpty
                            ? row.subject
                            : 'posta.noSubject'.tr(),
                      ),
                      subtitle: Text(
                        [
                          row.inbound
                              ? 'posta.directionIn'.tr()
                              : 'posta.directionOut'.tr(),
                          if (row.inbound &&
                              (row.linkedMensajeId ?? '').isNotEmpty)
                            'posta.threadReply'.tr(),
                          if ((row.counterpart ?? '').isNotEmpty)
                            row.counterpart!,
                          when,
                          if (row.attachmentCount > 0)
                            'posta.attachCount'.tr(
                              namedArgs: {
                                'count': '${row.attachmentCount}',
                              },
                            ),
                          if (row.unfiledCount > 0)
                            'posta.unfiledCount'.tr(
                              namedArgs: {'count': '${row.unfiledCount}'},
                            ),
                          if (row.bounced) 'posta.bounce'.tr(),
                          if (row.done) 'posta.status.done'.tr(),
                        ].join(' · '),
                      ),
                      onTap: () {
                        if (row.inbound) {
                          context.go('/posta/${row.id}');
                          return;
                        }
                        showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(
                              row.subject.isNotEmpty
                                  ? row.subject
                                  : 'posta.directionOut'.tr(),
                            ),
                            content: SizedBox(
                              width: 480,
                              child: SingleChildScrollView(
                                child: Text(
                                  (row.body ?? '').trim().isEmpty
                                      ? 'posta.noBody'.tr()
                                      : row.body!,
                                ),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: Text('clients.cancel'.tr()),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
