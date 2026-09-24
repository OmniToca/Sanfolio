import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../core/documents/documento_storage.dart';
import '../../core/documents/office_attach_button.dart';
import '../../core/documents/office_file_pick.dart';
import '../../core/money/cents.dart';
import '../../core/search/search_query_content.dart';
import '../../core/theme/app_theme.dart';
import 'ai_chat.dart';
import 'ai_providers.dart';
import 'extract_text.dart';
import 'paper_glance.dart';

/// Trvalý panel. Search / open / prefill / extract; uložení je gesto gestora.
class AiPanel extends ConsumerStatefulWidget {
  const AiPanel({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  ConsumerState<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends ConsumerState<AiPanel> {
  final _q = TextEditingController();
  final _scroll = ScrollController();
  var _working = false;

  @override
  void dispose() {
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(aiChatProvider);
    final busy = _working || (chat.valueOrNull?.busy ?? false);
    ref.listen<AsyncValue<AiChatState>>(aiChatProvider, (prev, next) {
      final was = prev?.valueOrNull?.messages.length ?? 0;
      final now = next.valueOrNull?.messages.length ?? 0;
      final loaded =
          (prev?.isLoading ?? true) && next.hasValue && now > 0;
      if ((now > was || loaded) && (_working || _nearLatest() || loaded)) {
        _pinToLatest();
      }
    });
    return ColoredBox(
      color: AppTheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'ai.title'.tr(),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'ai.newThread'.tr(),
                  onPressed: busy
                      ? null
                      : () => ref.read(aiChatProvider.notifier).newThread(),
                  icon: const Icon(Icons.note_add_outlined),
                ),
                if (widget.onClose != null)
                  IconButton(
                    tooltip: 'ai.closePanel'.tr(),
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'ai.savedHint'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: chat.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('ai.writeError'.tr())),
              data: (state) {
                if (state.messages.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('ai.emptyThread'.tr()),
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                  itemCount: state.messages.length,
                  itemBuilder: (context, i) {
                    // Chronologicky ASC: staré nahoře, nové dole (Leo-styl).
                    // reverse:true + index flip po reloadu otáčel celý thread.
                    final message = state.messages[i];
                    return _Bubble(
                      message: message,
                      onOpen: (route) => context.go(route),
                      onPrefill: busy
                          ? null
                          : (fields, clienteId) =>
                                _openPrefill(fields, clienteId),
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _q,
                  minLines: 1,
                  maxLines: 4,
                  enabled: !busy,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) {
                    if (!busy) _send();
                  },
                  decoration: InputDecoration(
                    hintText: 'ai.input'.tr(),
                    suffixIcon: IconButton(
                      tooltip: 'ai.send'.tr(),
                      onPressed: busy ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 0,
                  children: [
                    TextButton(
                      onPressed: busy ? null : _extract,
                      child: Text('ai.extract'.tr()),
                    ),
                    OfficeAttachButton(
                      enabled: !busy,
                      icon: null,
                      label: 'ai.extractFile'.tr(),
                      onPicked: _extractPicked,
                    ),
                    TextButton(
                      onPressed: busy ? null : _draftMessage,
                      child: Text('ai.draftMessage'.tr()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _clienteId() {
    return clienteIdFromOfficePath(GoRouterState.of(context).uri.path);
  }

  Future<void> _send() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    setState(() => _working = true);
    final locale = context.locale.languageCode;
    try {
      await ref.read(aiChatProvider.notifier).addUser(q);
      _q.clear();
      final openId = _clienteId();
      final tenantId = ref
          .read(authControllerProvider)
          .valueOrNull
          ?.currentTenantId;
      final assistant = await askAiAssistant(
        message: q,
        locale: locale,
        clienteId: openId,
        tenantId: tenantId,
      );
      if (assistant != null) {
        await ref
            .read(aiChatProvider.notifier)
            .addAssistant(encodeAiChatPayload(assistant));
      } else {
        // Fallback bez Edge: seznam / search (stopslova+NIE) / facts karty.
        final listAll = looksLikeListClientsQuery(q);
        final hits =
            listAll ? await aiListClients() : await aiSearchClients(q);
        final facts = openId != null
            ? await askClienteFactsForId(openId)
            : (listAll || hits.isEmpty
                  ? null
                  : await askClienteFactsForId(
                      hits.first.clienteId,
                      nombre: hits.first.nombre,
                    ));
        final office = tenantId == null
            ? null
            : await askOfficeFacts(tenantId: tenantId, q: q);
        await ref
            .read(aiChatProvider.notifier)
            .addAssistant(
              encodeAiChatPayload(
                _replyPayload(hits: hits, facts: facts, office: office),
              ),
            );
      }
      _pinToLatest();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ai.writeError'.tr())));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  AiChatPayload _replyPayload({
    required List<AiHit> hits,
    required AiFactAnswer? facts,
    AiOfficeAnswer? office,
  }) {
    if (facts == null && hits.isEmpty && office == null) {
      return AiChatPayload(text: 'ai.factsNone'.tr());
    }
    final lines = <String>[];
    final opens = <AiChatOpen>[];
    if (facts != null) {
      lines.add('ai.factsTitle'.tr(namedArgs: {'name': facts.nombre}));
      if (facts.nie != null && facts.nie!.isNotEmpty) {
        lines.add('${'fields.nie'.tr()}: ${facts.nie}');
      }
      if (facts.tel != null && facts.tel!.isNotEmpty) {
        lines.add('${'fields.tel'.tr()}: ${facts.tel}');
      }
      if (facts.email != null && facts.email!.isNotEmpty) {
        lines.add('${'fields.email'.tr()}: ${facts.email}');
      }
      if (facts.docs.isEmpty) {
        if (!facts.hasAnything) {
          lines.add('ai.factsEmpty'.tr());
        }
      } else {
        final glance = stackGlanceOf([
          for (final doc in facts.docs)
            (
              tipo: doc.tipo,
              fields: {
                if (doc.amount != null) 'fields.amount': doc.amount!,
                if (doc.consumption != null)
                  'fields.consumption': doc.consumption!,
                if (doc.periodFrom != null)
                  'fields.periodFrom': doc.periodFrom!,
                if (doc.periodTo != null) 'fields.periodTo': doc.periodTo!,
              },
            ),
        ]);
        if (glance.invoiceCount > 0) {
          lines.add(
            'folder.stackPaid'.tr(
              namedArgs: {
                'count': '${glance.invoiceCount}',
                'total': formatCents(glance.paidCents),
              },
            ),
          );
        }
        for (final doc in facts.docs) {
          final g = paperGlanceOf(
            tipo: doc.tipo,
            fields: {
              if (doc.amount != null) 'fields.amount': doc.amount!,
              if (doc.periodFrom != null) 'fields.periodFrom': doc.periodFrom!,
              if (doc.periodTo != null) 'fields.periodTo': doc.periodTo!,
              if (doc.consumption != null)
                'fields.consumption': doc.consumption!,
            },
          );
          if (g.isInvoice) {
            final period = paperPeriodRaw(g) ?? '';
            lines.add(
              [
                'docs.${doc.tipo}'.tr(),
                _aiAlbumBit(doc.albums),
                if ((doc.direccion ?? '').isNotEmpty) doc.direccion!,
                if (period.isNotEmpty) period,
                if (g.amountCents != null)
                  'folder.money'.tr(
                    namedArgs: {'amount': formatCents(g.amountCents!)},
                  ),
              ].join(' · '),
            );
            continue;
          }
          final bits = [
            'docs.${doc.tipo}'.tr(),
            _aiAlbumBit(doc.albums),
            if ((doc.direccion ?? '').isNotEmpty) doc.direccion!,
            if (doc.nie != null && doc.nie!.isNotEmpty)
              '${'fields.nie'.tr()}: ${doc.nie}',
            if (doc.docNumber != null && doc.docNumber!.isNotEmpty)
              '${'fields.docNumber'.tr()}: ${doc.docNumber}',
            if (doc.expiry != null && doc.expiry!.isNotEmpty)
              '${'fields.expiry'.tr()}: ${doc.expiry}',
            if ((doc.aiSummary ?? '').trim().isNotEmpty) doc.aiSummary!.trim(),
          ];
          lines.add(bits.join(' · '));
        }
      }
      opens.add(
        AiChatOpen(
          clienteId: facts.clienteId,
          label: facts.nombre,
          carpeta: true,
        ),
      );
    }
    if (office != null) {
      if (lines.isNotEmpty) lines.add('');
      lines.add('ai.officeHits'.tr());
      if (!office.filledOnDesk || office.items.isEmpty) {
        lines.add('ai.officeEmpty'.tr());
      } else {
        lines.add('ai.officePartial'.tr());
        for (final hit in office.items) {
          lines.add(
            [
              hit.nombre,
              _aiAlbumBit(hit.albums),
              if ((hit.direccion ?? '').isNotEmpty) hit.direccion!,
              if (hit.detail != null) hit.detail!,
            ].join(' · '),
          );
          if (opens.any(
            (o) =>
                o.clienteId == hit.clienteId &&
                o.bloqueKey == hit.bloqueKey,
          )) {
            continue;
          }
          opens.add(
            AiChatOpen(
              clienteId: hit.clienteId,
              label: hit.nombre,
              carpeta: true,
              bloqueKey: hit.bloqueKey,
            ),
          );
        }
        if (office.total > office.items.length) {
          lines.add('${office.items.length}/${office.total}');
        }
      }
    }
    if (hits.isNotEmpty) {
      if (lines.isNotEmpty) lines.add('');
      lines.add('ai.results'.tr());
      for (final hit in hits) {
        final name = hit.nombre.isEmpty ? 'inbox.unnamed'.tr() : hit.nombre;
        lines.add(name);
        if (opens.any((o) => o.clienteId == hit.clienteId)) continue;
        opens.add(AiChatOpen(clienteId: hit.clienteId, label: name));
      }
    }
    return AiChatPayload(text: lines.join('\n'), opens: opens);
  }

  Future<void> _openPrefill(
    Map<String, String> fields, [
    String? clienteId,
  ]) async {
    final id = _clienteId() ?? clienteId;
    if (id == null || fields.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ai.needFolder'.tr())));
      return;
    }
    final tenantId = ref
        .read(authControllerProvider)
        .valueOrNull
        ?.currentTenantId;
    final draftId = tenantId == null
        ? null
        : await persistAiDraft(
            tenantId: tenantId,
            clienteId: id,
            fields: fields,
          );
    ref.read(aiPrefillProvider.notifier).state = AiPrefillDraft(
      draftId: draftId,
      clienteId: id,
      bloqueKey: 'cliente_snapshot',
      fields: fields,
    );
    if (!mounted) return;
    context.go('/clientes/$id/carpeta');
  }

  Future<void> _extract() async {
    final text = _q.text.trim();
    if (text.isEmpty) return;
    final extracted = extractFromText(text);
    setState(() => _working = true);
    try {
      await ref.read(aiChatProvider.notifier).addUser(text);
      _q.clear();
      if (extracted.isEmpty) {
        await ref
            .read(aiChatProvider.notifier)
            .addAssistant(
              encodeAiChatPayload(AiChatPayload(text: 'ai.extractEmpty'.tr())),
            );
        return;
      }
      final lines = [
        'ai.proposal'.tr(),
        if (extracted.nie != null) '${'fields.nie'.tr()}: ${extracted.nie}',
        if (extracted.email != null)
          '${'fields.email'.tr()}: ${extracted.email}',
        if (extracted.tel != null) '${'fields.tel'.tr()}: ${extracted.tel}',
        if (extracted.iban != null)
          '${'fields.iban'.tr()}: ${formatIban(extracted.iban!)}',
        if (extracted.nombre != null)
          '${'fields.nombre'.tr()}: ${extracted.nombre}',
      ];
      await ref
          .read(aiChatProvider.notifier)
          .addAssistant(
            encodeAiChatPayload(
              AiChatPayload(
                text: lines.join('\n'),
                fields: extracted.snapshotFields,
              ),
            ),
          );
      _pinToLatest();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ai.writeError'.tr())));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _extractPicked(PickedOfficeFile file) async {
    final id = _clienteId();
    final tenantId = ref
        .read(authControllerProvider)
        .valueOrNull
        ?.currentTenantId;
    if (id == null || tenantId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ai.needFolder'.tr())));
      return;
    }
    setState(() => _working = true);
    try {
      if (trySupabaseClient() == null) {
        throw OfficeUploadException('not_configured');
      }
      final ingested = await ingestClienteDocumento(
        tenantId: tenantId,
        clienteId: id,
        bytes: file.bytes,
        originalName: file.name,
      );
      await ref.read(aiChatProvider.notifier).addUser(file.name);
      await ref.read(aiChatProvider.notifier).addAssistant(
            encodeAiChatPayload(AiChatPayload(text: 'ai.readingDoc'.tr())),
          );
      startExtractInBackground(
        tenantId: tenantId,
        clienteId: id,
        storagePath: ingested.storagePath,
        mime: mimeForOfficeFile(file.name, extension: file.extension),
        onDone: (draft) {
          if (draft == null || isExtractFailed(draft.fields)) {
            unawaited(
              ref.read(aiChatProvider.notifier).addAssistant(
                    encodeAiChatPayload(
                      AiChatPayload(text: 'ai.extractEmpty'.tr()),
                    ),
                  ),
            );
            return;
          }
          if (isExtractPending(draft.fields)) {
            ref.invalidate(liveAiDraftsProvider(id));
            return;
          }
          ref.read(aiPrefillProvider.notifier).state = draft;
          unawaited(
            ref.read(aiChatProvider.notifier).addAssistant(
                  encodeAiChatPayload(
                    AiChatPayload(
                      text: 'ai.proposal'.tr(),
                      fields: draft.fields,
                      opens: [
                        AiChatOpen(
                          clienteId: id,
                          label: file.name,
                          carpeta: true,
                        ),
                      ],
                    ),
                  ),
                ),
          );
        },
      );
      ref.invalidate(liveAiDraftsProvider(id));
      if (!mounted) return;
      context.go('/clientes/$id/carpeta');
    } on Object catch (e) {
      if (mounted) showOfficeUploadFailure(context, e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _draftMessage() async {
    final id = _clienteId();
    final tenantId = ref
        .read(authControllerProvider)
        .valueOrNull
        ?.currentTenantId;
    if (id == null || tenantId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ai.needFolder'.tr())));
      return;
    }
    setState(() => _working = true);
    try {
      final draft = await draftMessageFromHoles(
        tenantId: tenantId,
        clienteId: id,
      );
      await ref.read(aiChatProvider.notifier).addUser('ai.draftMessage'.tr());
      await ref
          .read(aiChatProvider.notifier)
          .addAssistant(
            encodeAiChatPayload(
              AiChatPayload(
                text: 'ai.proposal'.tr(),
                opens: [
                  AiChatOpen(
                    clienteId: id,
                    label: 'ai.draftMessage'.tr(),
                    carpeta: false,
                  ),
                ],
              ),
            ),
          );
      if (!mounted) return;
      final bloque = Uri.encodeQueryComponent(draft.bloqueKey);
      context.go(
        '/clientes/$id/mensaje?tpl=${draft.templateKey}&bloque=$bloque',
      );
    } on Object catch (e) {
      if (!mounted) return;
      final msg = '$e'.contains('no_holes')
          ? 'ai.noHoles'.tr()
          : 'ai.draftError'.tr();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  bool _nearLatest() {
    if (!_scroll.hasClients) return true;
    final pos = _scroll.position;
    return pos.maxScrollExtent - pos.pixels <= 72;
  }

  /// ASC seznam: nejnovější dole u vstupu. Po reloadu i po odpovědi.
  void _pinToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.onOpen,
    required this.onPrefill,
  });

  final AiChatMessage message;
  final ValueChanged<String> onOpen;
  final void Function(Map<String, String> fields, String? clienteId)? onPrefill;

  @override
  Widget build(BuildContext context) {
    final payload = decodeAiChatPayload(message.content);
    final mine = message.fromUser;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: mine ? AppTheme.accentSoft : AppTheme.paper,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(color: AppTheme.rule),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payload.text),
                if (payload.opens.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final open in payload.opens)
                    TextButton(
                      onPressed: () => onOpen(open.route),
                      child: Text(_openLabel(open)),
                    ),
                ],
                if (!mine &&
                    payload.fields.isNotEmpty &&
                    onPrefill != null) ...[
                  TextButton(
                    onPressed: () => onPrefill!(
                      payload.fields,
                      payload.opens.isEmpty
                          ? null
                          : payload.opens.first.clienteId,
                    ),
                    child: Text('ai.prefill'.tr()),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _openLabel(AiChatOpen open) {
  final name = open.label.isEmpty ? 'inbox.unnamed'.tr() : open.label;
  if (open.opensFolderDesk) {
    return 'ai.openFolder'.tr(namedArgs: {'name': name});
  }
  return name;
}

/// Prázdné albums z RPC = hromada, jinak názvy bloků.
String _aiAlbumBit(List<String> albums) {
  if (albums.isEmpty) return 'stoh.pile'.tr();
  return albums.map((k) => 'blocks.$k'.tr()).join(' · ');
}
