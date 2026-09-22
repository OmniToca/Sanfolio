import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money/cents.dart';
import 'office_modules_provider.dart';

/// Globální ceník modulů. Sleva je na kanceláři, ne tady.
class CenikScreen extends ConsumerWidget {
  const CenikScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(moduleCatalogProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('cenik.title'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/tenants'),
        ),
      ),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(child: Text('tenants.modulesEmpty'.tr()));
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('cenik.hint'.tr()),
              const SizedBox(height: 16),
              for (final row in list) _PriceRow(row: row),
            ],
          );
        },
      ),
    );
  }
}

class _PriceRow extends ConsumerStatefulWidget {
  const _PriceRow({required this.row});

  final CatalogPrice row;

  @override
  ConsumerState<_PriceRow> createState() => _PriceRowState();
}

class _PriceRowState extends ConsumerState<_PriceRow> {
  late final TextEditingController _cents;

  @override
  void initState() {
    super.initState();
    _cents = TextEditingController(text: formatCents(widget.row.cents));
  }

  @override
  void didUpdateWidget(covariant _PriceRow oldWidget) {
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
