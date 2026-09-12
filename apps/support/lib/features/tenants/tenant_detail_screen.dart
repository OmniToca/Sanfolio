import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import 'offices_provider.dart';

class TenantDetailScreen extends ConsumerWidget {
  const TenantDetailScreen({super.key, required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offices = ref.watch(officesProvider);
    final row = offices.valueOrNull
        ?.where((o) => o.id == tenantId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(row?.label ?? 'tenants.detail'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/tenants'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('tenants.impersonateHint'.tr()),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _impersonate(context, ref),
              icon: const Icon(Icons.switch_account),
              label: Text('tenants.impersonate'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _impersonate(BuildContext context, WidgetRef ref) async {
    final reason = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('tenants.impersonate'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reason,
              decoration: InputDecoration(labelText: 'tenants.reason'.tr()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: note,
              decoration: InputDecoration(labelText: 'tenants.note'.tr()),
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
            child: Text('tenants.impersonate'.tr()),
          ),
        ],
      ),
    );
    final reasonText = reason.text.trim();
    final noteText = note.text.trim();
    reason.dispose();
    note.dispose();
    if (ok != true || !context.mounted) return;
    if (reasonText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('tenants.reasonRequired'.tr())),
      );
      return;
    }
    try {
      await ref.read(authControllerProvider.notifier).startImpersonation(
            tenantId: tenantId,
            reason: reasonText,
            note: noteText,
          );
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}
