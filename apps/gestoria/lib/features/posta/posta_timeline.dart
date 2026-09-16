import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mensajes/mensaje_providers.dart';
import 'posta_providers.dart';

/// Jeden řádek na kartě: mail od klienta, nebo výzva kanceláře jemu.
enum ClienteMailDirection { inbound, outbound }

class ClienteMailItem {
  const ClienteMailItem({
    required this.id,
    required this.direction,
    required this.at,
    required this.subject,
    this.counterpart,
    this.attachmentCount = 0,
    this.unfiledCount = 0,
    this.body,
    this.linkedMensajeId,
  });

  final String id;
  final ClienteMailDirection direction;
  final DateTime at;
  final String subject;
  final String? counterpart;
  final int attachmentCount;
  final int unfiledCount;
  final String? body;
  final String? linkedMensajeId;

  bool get inbound => direction == ClienteMailDirection.inbound;
}

/// Novější nahoře. WhatsApp do tohoto seznamu nepatří — to je jiný kanál.
List<ClienteMailItem> mergeClienteMail({
  required List<PostaMessage> inbound,
  required List<ClienteMensaje> outbound,
}) {
  final out = <ClienteMailItem>[
    for (final m in inbound)
      if (m.status != 'ignored')
        ClienteMailItem(
          id: m.id,
          direction: ClienteMailDirection.inbound,
          at: m.receivedAt,
          subject: (m.subject ?? '').trim(),
          counterpart: m.fromLabel,
          attachmentCount: m.attachments.length,
          unfiledCount: m.unfiledCount,
          body: m.bodyText,
          linkedMensajeId: m.mensajeId,
        ),
    for (final m in outbound)
      if (m.status == 'sent' && (m.canal == null || m.canal == 'email'))
        ClienteMailItem(
          id: m.id,
          direction: ClienteMailDirection.outbound,
          at: m.sentAt ?? m.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          subject: (m.asunto ?? '').trim(),
          counterpart: null,
          body: m.cuerpo,
        ),
  ]..sort((a, b) => b.at.compareTo(a.at));
  return out;
}

final clienteMailTimelineProvider =
    FutureProvider.family<List<ClienteMailItem>, String>((ref, clienteId) async {
  final inbound = await ref.watch(clientePostaProvider(clienteId).future);
  final outbound = await ref.watch(clienteMensajesProvider(clienteId).future);
  return mergeClienteMail(inbound: inbound, outbound: outbound);
});
