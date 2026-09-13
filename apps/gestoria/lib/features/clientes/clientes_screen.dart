import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../settings/office_settings_controller.dart';
import 'clientes_providers.dart';

class ClientesScreen extends ConsumerStatefulWidget {
  const ClientesScreen({super.key});

  @override
  ConsumerState<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends ConsumerState<ClientesScreen> {
  Timer? _searchDebounce;
  final _search = TextEditingController();

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(clientesListProvider);
    final office =
        ref.watch(officeSettingsProvider).valueOrNull?.displayName ?? '';
    final filter = ref.watch(clientesFilterProvider);
    final showDeleted = canRestoreDeleted(
      ref.watch(authControllerProvider).valueOrNull ?? AuthSnapshot.signedOut,
    );
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final rows = list.valueOrNull ?? const <ClienteRow>[];
    return Scaffold(
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
                    kicker: office.isEmpty ? null : office,
                    title: 'clients.title'.tr(),
                    subtitle: 'clients.onShelf'.tr(
                      namedArgs: {'count': '${rows.length}'},
                    ),
                    actions: [
                      if (wide)
                        FilledButton.icon(
                          onPressed: () => _createCliente(context, ref),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text('clients.newFolder'.tr()),
                        )
                      else
                        IconButton.filled(
                          tooltip: 'clients.newFolder'.tr(),
                          onPressed: () => _createCliente(context, ref),
                          icon: const Icon(Icons.add),
                        ),
                    ],
                    bottom: AppTextField(
                      label: 'clients.searchHint'.tr(),
                      prefixIcon: const Icon(Icons.search),
                      controller: _search,
                      onChanged: (v) {
                        _searchDebounce?.cancel();
                        _searchDebounce = Timer(
                          const Duration(milliseconds: 300),
                          () {
                            ref.read(clientesQueryProvider.notifier).state = v;
                          },
                        );
                      },
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppStamp(
                        label: 'clients.filterActive'.tr(),
                        selected: filter == ClientesListFilter.activo,
                        onTap: () =>
                            ref.read(clientesFilterProvider.notifier).state =
                                ClientesListFilter.activo,
                      ),
                      AppStamp(
                        label: 'clients.filterInactive'.tr(),
                        selected: filter == ClientesListFilter.inactivo,
                        onTap: () =>
                            ref.read(clientesFilterProvider.notifier).state =
                                ClientesListFilter.inactivo,
                      ),
                      if (showDeleted)
                        AppStamp(
                          label: 'clients.filterDeleted'.tr(),
                          selected: filter == ClientesListFilter.deleted,
                          onTap: () =>
                              ref.read(clientesFilterProvider.notifier).state =
                                  ClientesListFilter.deleted,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (list.isLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (list.hasError)
                    Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Text('clients.loadError'.tr()),
                    )
                  else if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Text(
                        'clients.empty'.tr(),
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(color: AppTheme.pencil),
                      ),
                    )
                  else
                    for (final row in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                          stripe: row.deleted
                              ? AppTheme.pencil
                              : row.status == 'inactivo'
                              ? AppTheme.rule
                              : row.isCoOwnerOnly
                              ? AppTheme.rule
                              : AppTheme.accent,
                          onTap: () => context.go('/clientes/${row.id}'),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        row.nombre,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      if (row.isCoOwnerOnly) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'clients.coOwner'.tr(
                                            namedArgs: {
                                              'owner': row.coOwnerNombre ?? '',
                                              'address':
                                                  row.coOwnerAddress ?? '',
                                            },
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: AppTheme.pencil),
                                        ),
                                      ],
                                      if (row.subtitle.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          row.subtitle,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (_statusLabel(row).isNotEmpty)
                                  Text(
                                    _statusLabel(row),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  )
                                else
                                  const Icon(
                                    Icons.chevron_right,
                                    color: AppTheme.pencil,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(ClienteRow row) {
    if (row.deleted) return 'clients.filterDeleted'.tr();
    if (row.status == 'inactivo') return 'clients.statusInactivo'.tr();
    if (row.isCoOwnerOnly) return 'clients.coOwnerShort'.tr();
    return '';
  }
}

Future<void> _createCliente(BuildContext context, WidgetRef ref) async {
  final tenantId = ref
      .read(authControllerProvider)
      .valueOrNull
      ?.currentTenantId;
  if (tenantId == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('clients.createError'.tr())));
    return;
  }
  final nombre = TextEditingController();
  final nie = TextEditingController();
  final email = TextEditingController();
  final tel = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('clients.newFolder'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nombre,
            autofocus: true,
            decoration: InputDecoration(labelText: 'clients.name'.tr()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: nie,
            decoration: InputDecoration(labelText: 'clients.nieOptional'.tr()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: 'fields.email'.tr()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: tel,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: 'fields.tel'.tr()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('clients.cancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('clients.create'.tr()),
        ),
      ],
    ),
  );
  final name = nombre.text.trim();
  final nieVal = nie.text.trim();
  final emailVal = email.text.trim();
  final telVal = tel.text.trim();
  nombre.dispose();
  nie.dispose();
  email.dispose();
  tel.dispose();
  if (ok != true || !context.mounted) return;
  if (name.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('clients.nameRequired'.tr())));
    return;
  }
  try {
    final id = await openCarpetaCompraventa(
      tenantId: tenantId,
      nombre: name,
      nie: nieVal.isEmpty ? null : nieVal,
      email: emailVal.isEmpty ? null : emailVal,
      tel: telVal.isEmpty ? null : telVal,
    );
    ref.invalidate(clientesListProvider);
    if (context.mounted) context.go('/clientes/$id/carpeta');
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('clients.createError'.tr())));
    }
  }
}
