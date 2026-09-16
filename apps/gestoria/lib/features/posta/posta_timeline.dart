import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mensajes/mensaje_providers.dart';
import 'posta_address.dart';
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
    this.bounced = false,
    this.bounceReason,
    this.done = false,
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
  final bool bounced;
  final String? bounceReason;
  final bool done;

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
          done: m.isDone,
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
          bounced: m.bounceAt != null,
          bounceReason: m.bounceReason,
        ),
  ]..sort((a, b) => b.at.compareTo(a.at));
  return out;
}

final clienteMailTimelineProvider =
    FutureProvider.family<List<ClienteMailItem>, String>((ref, clienteId) async {
  ref.watch(postaRealtimeTickProvider);
  final inbound = await ref.watch(clientePostaProvider(clienteId).future);
  final outbound = await ref.watch(clienteMensajesProvider(clienteId).future);
  return mergeClienteMail(inbound: inbound, outbound: outbound);
});

/// Položka vlákna v náhledu mailu (starší nahoře).
class PostaThreadItem {
  const PostaThreadItem({
    required this.id,
    required this.inbound,
    required this.at,
    required this.subject,
    this.body,
    this.current = false,
    this.bounced = false,
  });

  final String id;
  final bool inbound;
  final DateTime at;
  final String subject;
  final String? body;
  final bool current;
  final bool bounced;
}

bool _sameThread(PostaMessage a, PostaMessage b) {
  if (a.id == b.id) return true;
  final sub = normalizePostaSubject(a.subject);
  if (sub.isNotEmpty && sub == normalizePostaSubject(b.subject)) return true;
  final aMsg = a.mensajeId ?? '';
  final bMsg = b.mensajeId ?? '';
  if (aMsg.isNotEmpty && aMsg == bMsg) return true;
  final hay = '${a.inReplyTo ?? ''} ${a.referencesHeader ?? ''} '
      '${b.inReplyTo ?? ''} ${b.referencesHeader ?? ''}';
  final aId = a.messageIdHeader ?? '';
  final bId = b.messageIdHeader ?? '';
  if (aId.isNotEmpty && hay.contains(aId)) return true;
  if (bId.isNotEmpty && hay.contains(bId)) return true;
  return false;
}

List<PostaThreadItem> buildPostaThread({
  required PostaMessage current,
  required List<PostaMessage> inbound,
  required List<ClienteMensaje> outbound,
}) {
  final relatedIn = [
    for (final m in inbound)
      if (m.status != 'ignored' && _sameThread(current, m)) m,
  ];
  if (relatedIn.every((m) => m.id != current.id)) {
    relatedIn.add(current);
  }
  final sub = normalizePostaSubject(current.subject);
  final msgId = current.mensajeId ?? '';
  final hay = '${current.inReplyTo ?? ''} ${current.referencesHeader ?? ''}';
  final relatedOut = [
    for (final m in outbound)
      if (m.status == 'sent' && (m.canal == null || m.canal == 'email'))
        if ((msgId.isNotEmpty && m.id == msgId) ||
            (sub.isNotEmpty && sub == normalizePostaSubject(m.asunto)) ||
            ((m.messageIdHeader ?? '').isNotEmpty &&
                hay.contains(m.messageIdHeader!)))
          m,
  ];
  final items = <PostaThreadItem>[
    for (final m in relatedIn)
      PostaThreadItem(
        id: m.id,
        inbound: true,
        at: m.receivedAt,
        subject: (m.subject ?? '').trim(),
        body: m.bodyText,
        current: m.id == current.id,
      ),
    for (final m in relatedOut)
      PostaThreadItem(
        id: m.id,
        inbound: false,
        at: m.sentAt ?? m.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        subject: (m.asunto ?? '').trim(),
        body: m.cuerpo,
        bounced: m.bounceAt != null,
      ),
  ]..sort((a, b) => a.at.compareTo(b.at));
  return items;
}

final postaThreadProvider =
    FutureProvider.family<List<PostaThreadItem>, String>((ref, messageId) async {
  final current = await ref.watch(postaDetailProvider(messageId).future);
  if (current == null) return [];
  final clienteId = current.clienteId;
  if (clienteId == null || clienteId.isEmpty) {
    return buildPostaThread(
      current: current,
      inbound: [current],
      outbound: const [],
    );
  }
  final inbound = await ref.watch(clientePostaProvider(clienteId).future);
  final outbound = await ref.watch(clienteMensajesProvider(clienteId).future);
  return buildPostaThread(
    current: current,
    inbound: inbound,
    outbound: outbound,
  );
});
