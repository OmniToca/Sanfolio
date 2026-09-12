import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../core/presentation/widgets/app_widgets.dart';
import 'clientes_providers.dart';

class ClientesScreen extends ConsumerStatefulWidget {
  const ClientesScreen({super.key});

  @override
  ConsumerState<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends ConsumerState<ClientesScreen> {
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(clientesListProvider);
    return Scaffold(
      appBar: AppBar(title: Text('clients.title'.tr())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SearchBar(
              hintText: 'clients.searchHint'.tr(),
              leading: const Icon(Icons.search),
              onChanged: (v) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                  ref.read(clientesQueryProvider.notifier).state = v;
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _ClientesFilterBar(
                filter: ref.watch(clientesFilterProvider),
                showDeleted: canRestoreDeleted(
                  ref.watch(authControllerProvider).valueOrNull ??
                      AuthSnapshot.signedOut,
                ),
                onChanged: (v) =>
                    ref.read(clientesFilterProvider.notifier).state = v,
              ),
            ),
          ),
          Expanded(
            child: list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('clients.loadError'.tr())),
              data: (rows) {
                if (rows.isEmpty) {
                  return Center(child: Text('clients.empty'.tr()));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                  itemCount: rows.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    return AppCard(
                      onTap: () => context.go('/clientes/${row.id}'),
                      child: ListTile(
                        title: Text(row.nombre),
                        subtitle: row.subtitle.isEmpty ? null : Text(row.subtitle),
                        trailing: _statusLabel(row).isEmpty
                            ? const Icon(Icons.chevron_right)
                            : Text(_statusLabel(row)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createCliente(context, ref),
        icon: const Icon(Icons.add),
        label: Text('clients.newFolder'.tr()),
      ),
    );
  }

  String _statusLabel(ClienteRow row) {
    if (row.deleted) return 'clients.filterDeleted'.tr();
    if (row.status == 'inactivo') return 'clients.statusInactivo'.tr();
    return '';
  }
}

class _ClientesFilterBar extends StatelessWidget {
  const _ClientesFilterBar({
    required this.filter,
    required this.showDeleted,
    required this.onChanged,
  });

  final ClientesListFilter filter;
  final bool showDeleted;
  final ValueChanged<ClientesListFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = showDeleted || filter != ClientesListFilter.deleted
        ? filter
        : ClientesListFilter.activo;
    return SegmentedButton<ClientesListFilter>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: ClientesListFilter.activo,
          label: Text('clients.filterActive'.tr()),
        ),
        ButtonSegment(
          value: ClientesListFilter.inactivo,
          label: Text('clients.filterInactive'.tr()),
        ),
        if (showDeleted)
          ButtonSegment(
            value: ClientesListFilter.deleted,
            label: Text('clients.filterDeleted'.tr()),
          ),
      ],
      selected: {selected},
      onSelectionChanged: (next) => onChanged(next.first),
    );
  }
}

Future<void> _createCliente(BuildContext context, WidgetRef ref) async {
  final tenantId =
      ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (tenantId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('clients.createError'.tr())),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('clients.nameRequired'.tr())),
    );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('clients.createError'.tr())),
      );
    }
  }
}
