import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../facturacion/csv_save.dart';
import 'cliente_csv.dart';
import 'cliente_csv_pick.dart';
import 'clientes_providers.dart';

/// Náhled CSV a dávkové `open_carpeta_compraventa`. Stoh se samo neotevře.
class ClienteImportScreen extends ConsumerStatefulWidget {
  const ClienteImportScreen({super.key});

  @override
  ConsumerState<ClienteImportScreen> createState() =>
      _ClienteImportScreenState();
}

class _ClienteImportScreenState extends ConsumerState<ClienteImportScreen> {
  ClienteCsvParse? _parsed;
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;
    return Scaffold(
      appBar: AppBar(
        title: Text('clients.importTitle'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/clientes'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppTheme.contentWide),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppPageHeader(
                    title: 'clients.importTitle'.tr(),
                    subtitle: 'clients.importHint'.tr(),
                    actions: [
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => saveCsvFile(
                                'clientes.csv',
                                clienteCsvTemplate(),
                              ),
                        icon: const Icon(Icons.download, size: 18),
                        label: Text('clients.importTemplate'.tr()),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : _pick,
                        icon: const Icon(Icons.upload_file, size: 18),
                        label: Text('clients.importPick'.tr()),
                      ),
                    ],
                  ),
                  if (parsed == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Text('clients.importEmptyFile'.tr()),
                    )
                  else if (parsed.error == 'empty')
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Text('clients.importEmptyFile'.tr()),
                    )
                  else if (parsed.error == 'header')
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Text('clients.importBadHeader'.tr()),
                    )
                  else ...[
                    if (parsed.error == 'tooMany')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'clients.importTooMany'.tr(
                            namedArgs: {'max': '$clienteCsvMaxRows'},
                          ),
                        ),
                      ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          label: Text(
                            'clients.importPreviewReady'.tr(
                              namedArgs: {'count': '${parsed.readyCount}'},
                            ),
                          ),
                        ),
                        Chip(
                          label: Text(
                            'clients.importPreviewEmpty'.tr(
                              namedArgs: {'count': '${parsed.emptyCount}'},
                            ),
                          ),
                        ),
                        Chip(
                          label: Text(
                            'clients.importPreviewDup'.tr(
                              namedArgs: {'count': '${parsed.duplicateCount}'},
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        onPressed: _busy || parsed.readyCount == 0
                            ? null
                            : () => _run(parsed),
                        child: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text('clients.importRun'.tr()),
                      ),
                    ),
                    const SizedBox(height: 20),
                    for (final row in parsed.rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ImportRowCard(row: row),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pick() async {
    final text = await pickClienteCsvText();
    if (text == null || !mounted) return;
    final live = await _liveNies();
    if (!mounted) return;
    setState(() {
      _parsed = parseClienteCsv(text, liveNies: live);
    });
  }

  Future<Set<String>> _liveNies() async {
    final client = trySupabaseClient();
    final tenantId = ref
        .read(authControllerProvider)
        .valueOrNull
        ?.currentTenantId;
    if (client == null || tenantId == null) return {};
    try {
      final rows = await client
          .from('client_identifiers')
          .select('value_normalized')
          .eq('tenant_id', tenantId)
          .inFilter('kind', ['nie', 'dni', 'nif'])
          .isFilter('deleted_at', null);
      final out = <String>{};
      for (final raw in rows) {
        final n = normalizeCsvNie('${raw['value_normalized'] ?? ''}');
        if (n.isNotEmpty) out.add(n);
      }
      return out;
    } on Object {
      return {};
    }
  }

  Future<void> _run(ClienteCsvParse parsed) async {
    final tenantId = ref
        .read(authControllerProvider)
        .valueOrNull
        ?.currentTenantId;
    final client = trySupabaseClient();
    if (tenantId == null || client == null) {
      _toast('clients.importError'.tr());
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('clients.importRun'.tr()),
        content: Text(
          'clients.importConfirm'.tr(
            namedArgs: {
              'ready': '${parsed.readyCount}',
              'empty': '${parsed.emptyCount}',
              'dup': '${parsed.duplicateCount}',
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('clients.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('clients.importRun'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      var result = const ClienteCsvImportResult(
        created: 0,
        skippedEmpty: 0,
        skippedDuplicate: 0,
        errors: 0,
      );
      final chunks = chunkClienteCsvPayload(
        clienteCsvReadyPayload(parsed.rows),
      );
      for (final chunk in chunks) {
        final raw = await client.rpc(
          'import_carpeta_compraventa',
          params: {'p_tenant_id': tenantId, 'p_rows': chunk},
        );
        result = result + clienteCsvImportResultFromRpc(raw);
      }
      if (!mounted) return;
      ref.invalidate(clientesListProvider);
      _toast(
        'clients.importDone'.tr(
          namedArgs: {
            'created': '${result.created}',
            'empty': '${result.skippedEmpty + parsed.emptyCount}',
            'dup': '${result.skippedDuplicate + parsed.duplicateCount}',
            'errors': '${result.errors}',
          },
        ),
      );
    } on Object {
      if (mounted) _toast('clients.importError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _ImportRowCard extends StatelessWidget {
  const _ImportRowCard({required this.row});

  final ClienteCsvDraft row;

  @override
  Widget build(BuildContext context) {
    final bits = [
      if (row.nie.isNotEmpty) row.nie,
      if (row.email.isNotEmpty) row.email,
      if (row.tel.isNotEmpty) row.tel,
    ];
    final status = switch (row.status) {
      ClienteCsvStatus.ready => 'clients.importStatusReady'.tr(),
      ClienteCsvStatus.skipEmptyName => 'clients.importStatusEmpty'.tr(),
      ClienteCsvStatus.skipDuplicate => 'clients.importStatusDup'.tr(),
    };
    return AppCard(
      stripe: row.status == ClienteCsvStatus.ready
          ? AppTheme.statusOk
          : AppTheme.pencil,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              row.nombre.isEmpty ? 'inbox.unnamed'.tr() : row.nombre,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              [status, ...bits].join(' · '),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.pencil),
            ),
          ],
        ),
      ),
    );
  }
}
