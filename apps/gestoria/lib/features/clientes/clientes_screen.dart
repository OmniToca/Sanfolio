import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/staff_access.dart';
import '../../core/auth/staff_role.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../settings/office_settings_controller.dart';
import '../settings/office_team_controller.dart';
import '../carpeta/carpeta_routes.dart';
import 'clientes_providers.dart';
import 'poder_stamp.dart';

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
    final poderFilter = ref.watch(clientesPoderFilterProvider);
    final auth =
        ref.watch(authControllerProvider).valueOrNull ?? AuthSnapshot.signedOut;
    final showDeleted = canRestoreDeleted(auth);
    final staffScope =
        ref.watch(myStaffScopeProvider).valueOrNull ?? StaffAccessScope.open;
    final canCreate = staffMayCreateClientes(
      isOwner: currentOfficeRole(auth) == 'owner',
      scope: staffScope,
    );
    final canMerge = canMergeClientes(auth) && canCreate;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final allRows = list.valueOrNull ?? const <ClienteRow>[];
    final rows = [
      for (final row in allRows)
        if (poderFilter == ClientesPoderFilter.all ||
            (poderFilter == ClientesPoderFilter.withCopy &&
                row.poder.hasCopy) ||
            (poderFilter == ClientesPoderFilter.missing &&
                !row.poder.hasCopy))
          row,
    ];
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
                      if (canCreate)
                        if (wide)
                          OutlinedButton.icon(
                            onPressed: () => context.go('/clientes/import'),
                            icon: const Icon(Icons.upload_file, size: 18),
                            label: Text('clients.import'.tr()),
                          )
                        else
                          IconButton.outlined(
                            tooltip: 'clients.import'.tr(),
                            onPressed: () => context.go('/clientes/import'),
                            icon: const Icon(Icons.upload_file),
                          ),
                      if (canMerge)
                        if (wide)
                          OutlinedButton.icon(
                            onPressed: () => context.go('/clientes/sloucit'),
                            icon: const Icon(Icons.merge_type, size: 18),
                            label: Text('clients.merge'.tr()),
                          )
                        else
                          IconButton.outlined(
                            tooltip: 'clients.merge'.tr(),
                            onPressed: () => context.go('/clientes/sloucit'),
                            icon: const Icon(Icons.merge_type),
                          ),
                      if (canCreate)
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
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppStamp(
                        label: 'clients.filterPoderAll'.tr(),
                        selected: poderFilter == ClientesPoderFilter.all,
                        onTap: () => ref
                            .read(clientesPoderFilterProvider.notifier)
                            .state = ClientesPoderFilter.all,
                      ),
                      AppStamp(
                        label: 'clients.filterPoderYes'.tr(),
                        selected: poderFilter == ClientesPoderFilter.withCopy,
                        onTap: () => ref
                            .read(clientesPoderFilterProvider.notifier)
                            .state = ClientesPoderFilter.withCopy,
                      ),
                      AppStamp(
                        label: 'clients.filterPoderNo'.tr(),
                        selected: poderFilter == ClientesPoderFilter.missing,
                        onTap: () => ref
                            .read(clientesPoderFilterProvider.notifier)
                            .state = ClientesPoderFilter.missing,
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
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          PoderStamp(
                                            glance: row.poder,
                                            onOpen: row.poder.canOpenSource
                                                ? () => openPoderGlanceSource(
                                                      context: context,
                                                      glance: row.poder,
                                                      clienteId: row.id,
                                                      tenantId: ref
                                                          .watch(
                                                            authControllerProvider,
                                                          )
                                                          .valueOrNull
                                                          ?.currentTenantId,
                                                    )
                                                : null,
                                          ),
                                        ],
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
                                              ?.copyWith(
                                                color: AppTheme.pencil,
                                              ),
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
    if (context.mounted) {
      context.go(carpetaStohRoute(id, afterCreate: true));
    }
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('clients.createError'.tr())));
    }
  }
}
