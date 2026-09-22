import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import 'offices_provider.dart';

class TenantsScreen extends ConsumerWidget {
  const TenantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offices = ref.watch(officesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('tenants.title'.tr()),
        actions: [
          TextButton(
            onPressed: () => context.go('/cenik'),
            child: Text('cenik.title'.tr()),
          ),
          TextButton(
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
            child: Text('auth.signOut'.tr()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createOffice(context, ref),
        icon: const Icon(Icons.add),
        label: Text('tenants.new'.tr()),
      ),
      body: offices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(child: Text('tenants.empty'.tr()));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final row = list[i];
              return Card(
                child: ListTile(
                  title: Text(row.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/tenants/${row.id}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

Future<void> _createOffice(BuildContext context, WidgetRef ref) async {
  final name = TextEditingController();
  final email = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('tenants.new'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: InputDecoration(labelText: 'tenants.officeName'.tr()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: 'tenants.ownerEmail'.tr()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('auth.cancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('tenants.create'.tr()),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) {
    name.dispose();
    email.dispose();
    return;
  }
  try {
    final id = await ref.read(authControllerProvider.notifier).createOffice(
          name: name.text.trim(),
          ownerEmail: email.text.trim(),
          displayName: name.text.trim(),
        );
    ref.invalidate(officesProvider);
    if (context.mounted) context.go('/tenants/$id');
  } on Object catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  } finally {
    name.dispose();
    email.dispose();
  }
}
