import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../core/money/cents.dart';
import 'office_modules_provider.dart';
import 'offices_provider.dart';

class TenantDetailScreen extends ConsumerStatefulWidget {
  const TenantDetailScreen({super.key, required this.tenantId});

  final String tenantId;

  @override
  ConsumerState<TenantDetailScreen> createState() => _TenantDetailScreenState();
}

class _TenantDetailScreenState extends ConsumerState<TenantDetailScreen> {
  late final TextEditingController _discount;
  var _discountSeeded = false;

  @override
  void initState() {
    super.initState();
    _discount = TextEditingController();
  }

  @override
  void dispose() {
    _discount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offices = ref.watch(officesProvider);
    final licence = ref.watch(supportOfficeLicenceProvider(widget.tenantId));
    final row = offices.valueOrNull
        ?.where((o) => o.id == widget.tenantId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(row?.label ?? 'tenants.detail'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/tenants'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('tenants.impersonateHint'.tr()),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => _impersonate(context, ref),
              icon: const Icon(Icons.switch_account),
              label: Text('tenants.impersonate'.tr()),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'tenants.modulesTitle'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'tenants.modulesHint'.tr(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          licence.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
            data: (quote) {
              if (!_discountSeeded) {
                _discountSeeded = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _discount.text = '${quote.discountPercent}';
                });
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final line in quote.lines)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('modules.${line.key}'.tr()),
                      subtitle: Text(
                        'tenants.modulesPrice'.tr(
                          namedArgs: {'amount': formatCents(line.cents)},
                        ),
                      ),
                      value: line.on,
                      onChanged: line.alwaysOn
                          ? null
                          : (v) async {
                              await setSupportOfficeModule(
                                tenantId: widget.tenantId,
                                moduleKey: line.key,
                                on: v,
                              );
                              ref.invalidate(
                                supportOfficeLicenceProvider(widget.tenantId),
                              );
                            },
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _discount,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'tenants.discount'.tr(),
                      suffixText: '%',
                    ),
                    onSubmitted: (raw) => _saveDiscount(raw),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => _saveDiscount(_discount.text),
                      child: Text('tenants.saveDiscount'.tr()),
                    ),
                  ),
                  if (quote.discountBps > 0)
                    Text(
                      'tenants.discountOff'.tr(
                        namedArgs: {
                          'amount': formatCents(quote.discountCents),
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'tenants.monthly'.tr(
                      namedArgs: {'amount': formatCents(quote.totalCents)},
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _saveDiscount(String raw) async {
    final n = int.tryParse(raw.trim().replaceAll(',', '.').split('.').first);
    final percent = (n ?? 0).clamp(0, 100);
    await setSupportOfficeDiscount(
      tenantId: widget.tenantId,
      discountBps: percent * 100,
    );
    ref.invalidate(supportOfficeLicenceProvider(widget.tenantId));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('tenants.discountSaved'.tr())),
      );
    }
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
            tenantId: widget.tenantId,
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
