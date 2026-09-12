import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import 'ai_providers.dart';
import 'extract_text.dart';

Future<void> openAiSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: const AiSheet(),
    ),
  );
}

/// Search / open / extract. Žádné uložení ani odeslání.
class AiSheet extends ConsumerStatefulWidget {
  const AiSheet({super.key});

  @override
  ConsumerState<AiSheet> createState() => _AiSheetState();
}

class _AiSheetState extends ConsumerState<AiSheet> {
  final _q = TextEditingController();
  var _hits = const <AiHit>[];
  var _busy = false;
  ExtractedFields? _extracted;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ai.title'.tr(), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('ai.intro'.tr()),
            const SizedBox(height: 16),
            TextField(
              controller: _q,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: 'ai.input'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy ? null : _search,
                  child: Text('ai.search'.tr()),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _extract,
                  child: Text('ai.extract'.tr()),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _extractFile,
                  child: Text('ai.extractFile'.tr()),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _draftMessage,
                  child: Text('ai.draftMessage'.tr()),
                ),
              ],
            ),
            if (_hits.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('ai.results'.tr()),
              for (final hit in _hits)
                ListTile(
                  dense: true,
                  title: Text(
                    hit.nombre.isEmpty ? 'inbox.unnamed'.tr() : hit.nombre,
                  ),
                  subtitle: Text(
                    '${hit.matchedVia ?? ''} · ${hit.score}',
                  ),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () {
                    Navigator.pop(context);
                    context.go('/clientes/${hit.clienteId}');
                  },
                ),
            ],
            if (_extracted != null && !_extracted!.isEmpty) ...[
              const SizedBox(height: 16),
              Text('ai.proposal'.tr()),
              if (_extracted!.nie != null)
                Text('${'fields.nie'.tr()}: ${_extracted!.nie}'),
              if (_extracted!.email != null)
                Text('${'fields.email'.tr()}: ${_extracted!.email}'),
              if (_extracted!.tel != null)
                Text('${'fields.tel'.tr()}: ${_extracted!.tel}'),
              TextButton(
                onPressed: _busy ? null : _openPrefill,
                child: Text('ai.prefill'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? _clienteId() {
    final loc = GoRouterState.of(context).uri.path;
    final parts = loc.split('/');
    final i = parts.indexOf('clientes');
    if (i < 0 || i + 1 >= parts.length) return null;
    final id = parts[i + 1];
    if (id.isEmpty || id == 'carpeta') return null;
    return id;
  }

  Future<void> _openPrefill() async {
    final extracted = _extracted;
    final id = _clienteId();
    if (extracted == null || id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ai.needFolder'.tr())),
      );
      return;
    }
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    final draftId = tenantId == null
        ? null
        : await persistAiDraft(
            tenantId: tenantId,
            clienteId: id,
            fields: extracted.snapshotFields,
          );
    ref.read(aiPrefillProvider.notifier).state = AiPrefillDraft(
      draftId: draftId,
      clienteId: id,
      bloqueKey: 'cliente_snapshot',
      fields: extracted.snapshotFields,
    );
    if (!mounted) return;
    Navigator.pop(context);
    context.go('/clientes/$id/carpeta');
  }

  Future<void> _search() async {
    setState(() => _busy = true);
    try {
      final hits = await aiSearchClients(_q.text);
      if (mounted) setState(() => _hits = hits);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _extract() {
    setState(() => _extracted = extractFromText(_q.text));
  }

  Future<void> _extractFile() async {
    final id = _clienteId();
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    if (id == null || tenantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ai.needFolder'.tr())),
      );
      return;
    }
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ai.extractError'.tr())),
        );
      }
      return;
    }
    setState(() => _busy = true);
    try {
      final client = trySupabaseClient();
      if (client == null) throw StateError('not configured');
      final safe = file.name.replaceAll(RegExp(r'[/\\]'), '_').trim();
      final name = safe.isEmpty ? 'scan' : safe;
      final path =
          '$tenantId/$id/ai/${DateTime.now().microsecondsSinceEpoch}_$name';
      await client.storage.from('documentos').uploadBinary(path, bytes);
      final mime = _mimeFor(file.extension, file.name);
      final draft = await extractDocumentDraft(
        tenantId: tenantId,
        clienteId: id,
        storagePath: path,
        mime: mime,
      );
      if (!mounted) return;
      if (draft == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ai.extractEmpty'.tr())),
        );
        return;
      }
      ref.read(aiPrefillProvider.notifier).state = draft;
      Navigator.pop(context);
      context.go('/clientes/$id/carpeta');
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ai.extractError'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _mimeFor(String? ext, String name) {
    final e = (ext ?? name.split('.').last).toLowerCase();
    return switch (e) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      _ => 'image/jpeg',
    };
  }

  Future<void> _draftMessage() async {
    final id = _clienteId();
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    if (id == null || tenantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ai.needFolder'.tr())),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final draft = await draftMessageFromHoles(
        tenantId: tenantId,
        clienteId: id,
      );
      if (!mounted) return;
      Navigator.pop(context);
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
      if (mounted) setState(() => _busy = false);
    }
  }
}
