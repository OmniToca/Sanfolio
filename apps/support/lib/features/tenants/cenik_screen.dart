import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money/cents.dart';
import 'office_licence.dart';
import 'office_modules_provider.dart';

/// Globální ceník: 3 balíčky + doplňky. Sleva je na kanceláři, ne tady.
class CenikScreen extends ConsumerWidget {
  const CenikScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(licencePlansProvider);
    final catalog = ref.watch(moduleCatalogProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('cenik.title'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/tenants'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('cenik.plansHint'.tr()),
          const SizedBox(height: 16),
          plans.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
            data: (list) {
              if (list.isEmpty) {
                return Text('tenants.modulesEmpty'.tr());
              }
              return Column(
                children: [
                  for (final plan in list) _PlanPriceCard(plan: plan),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
          Text(
            'cenik.addons'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('cenik.addonsHint'.tr()),
          const SizedBox(height: 16),
          catalog.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
            data: (list) {
              final addOns = [
                for (final row in list)
                  if (LicenceAddonKeys.all.contains(row.key)) row,
              ];
              if (addOns.isEmpty) {
                return Text('tenants.modulesEmpty'.tr());
              }
              return Column(
                children: [
                  for (final row in addOns) _AddonPriceRow(row: row),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PlanPriceCard extends ConsumerStatefulWidget {
  const _PlanPriceCard({required this.plan});

  final LicencePlanInfo plan;

  @override
  ConsumerState<_PlanPriceCard> createState() => _PlanPriceCardState();
}

class _PlanPriceCardState extends ConsumerState<_PlanPriceCard> {
  late final TextEditingController _cents;

  @override
  void initState() {
    super.initState();
    _cents = TextEditingController(text: formatCents(widget.plan.cents));
  }

  @override
  void didUpdateWidget(covariant _PlanPriceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan.cents != widget.plan.cents) {
      _cents.text = formatCents(widget.plan.cents);
    }
  }

  @override
  void dispose() {
    _cents.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = parseEurosToCents(_cents.text) ?? 0;
    await setPlanCatalogPrice(planKey: widget.plan.key, cents: cents);
    ref.invalidate(licencePlansProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('cenik.saved'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final included = widget.plan.includedKeys.toList()..sort();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'plans.${widget.plan.key}Name'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('plans.${widget.plan.key}Hint'.tr()),
            if (included.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                [
                  for (final key in included) 'modules.$key'.tr(),
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _cents,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'cenik.monthly'.tr(),
                      suffixText: '€',
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                TextButton(onPressed: _save, child: Text('cenik.save'.tr())),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddonPriceRow extends ConsumerStatefulWidget {
  const _AddonPriceRow({required this.row});

  final CatalogPrice row;

  @override
  ConsumerState<_AddonPriceRow> createState() => _AddonPriceRowState();
}

class _AddonPriceRowState extends ConsumerState<_AddonPriceRow> {
  late final TextEditingController _cents;

  @override
  void initState() {
    super.initState();
    _cents = TextEditingController(text: formatCents(widget.row.cents));
  }

  @override
  void didUpdateWidget(covariant _AddonPriceRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.cents != widget.row.cents) {
      _cents.text = formatCents(widget.row.cents);
    }
  }

  @override
  void dispose() {
    _cents.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = parseEurosToCents(_cents.text) ?? 0;
    await setModuleCatalogPrice(moduleKey: widget.row.key, cents: cents);
    ref.invalidate(moduleCatalogProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('cenik.saved'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: Text('modules.${widget.row.key}'.tr())),
          SizedBox(
            width: 140,
            child: TextField(
              controller: _cents,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'cenik.monthly'.tr(),
                suffixText: '€',
              ),
              onSubmitted: (_) => _save(),
            ),
          ),
          TextButton(onPressed: _save, child: Text('cenik.save'.tr())),
        ],
      ),
    );
  }
}
