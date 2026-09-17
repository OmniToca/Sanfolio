import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/money/cents.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import 'office_offers.dart';
import 'office_offers_providers.dart';

/// Slot `settings.section`. Tarify, se kterými kancelář umí přepsat.
class OfertasSettingsSection extends ConsumerStatefulWidget {
  const OfertasSettingsSection({super.key});

  @override
  ConsumerState<OfertasSettingsSection> createState() =>
      _OfertasSettingsSectionState();
}

class _OfertasSettingsSectionState extends ConsumerState<OfertasSettingsSection> {
  final _title = TextEditingController();
  final _partner = TextEditingController();
  final _unit = TextEditingController();
  final _annual = TextEditingController();
  final _notes = TextEditingController();
  var _kind = 'luz';
  String? _editingId;
  var _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _partner.dispose();
    _unit.dispose();
    _annual.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _fill(OfficeOffer o) {
    _editingId = o.id;
    _kind = o.kind;
    _title.text = o.title;
    _partner.text = o.partner;
    _unit.text = o.unitCents == null ? '' : formatCents(o.unitCents!);
    _annual.text = o.annualCents == null ? '' : formatCents(o.annualCents!);
    _notes.text = o.notes;
  }

  void _clear() {
    _editingId = null;
    _title.clear();
    _partner.clear();
    _unit.clear();
    _annual.clear();
    _notes.clear();
  }

  Future<void> _save() async {
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    if (tenantId == null) return;
    setState(() => _busy = true);
    final ok = await saveOfficeOffer(
      tenantId: tenantId,
      id: _editingId,
      kind: _kind,
      title: _title.text,
      partner: _partner.text,
      unitCents: parseEurosToCents(_unit.text),
      annualCents: parseEurosToCents(_annual.text),
      notes: _notes.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _clear();
      ref.invalidate(officeOffersProvider);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ofertas.saveError'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(officeOffersProvider);
    return FeatureGate(
      module: GestoriaModule.ofertas,
      child: AppSectionCard(
        title: 'ofertas.settingsTitle'.tr(),
        hint: 'ofertas.settingsHint'.tr(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
              error: (e, st) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('ofertas.loadError'.tr()),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('ofertas.empty'.tr()),
                  );
                }
                return Column(
                  children: [
                    for (final o in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppInsetRow(
                          title: o.title,
                          subtitle: [
                            'ofertas.kind.${o.kind}'.tr(),
                            if (o.partner.isNotEmpty) o.partner,
                            if (o.unitCents != null)
                              '${formatCents(o.unitCents!)} €/${'folder.measureKwh'.tr()}',
                            if (o.annualCents != null)
                              '${formatCents(o.annualCents!)} €/${'ofertas.year'.tr()}',
                          ].join(' · '),
                          onTap: () => setState(() => _fill(o)),
                          trailing: TextButton(
                            onPressed: () async {
                              await hideOfficeOffer(o.id);
                              ref.invalidate(officeOffersProvider);
                              if (_editingId == o.id) _clear();
                            },
                            child: Text('ofertas.remove'.tr()),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in officeOfferKinds)
                  AppStamp(
                    label: 'ofertas.kind.$k'.tr(),
                    selected: _kind == k,
                    onTap: () => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            AppTextField(
              label: 'ofertas.title'.tr(),
              controller: _title,
            ),
            const SizedBox(height: 8),
            AppTextField(
              label: 'ofertas.partner'.tr(),
              controller: _partner,
            ),
            const SizedBox(height: 8),
            AppTextField(
              label: 'ofertas.unit'.tr(),
              controller: _unit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            AppTextField(
              label: 'ofertas.annual'.tr(),
              controller: _annual,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            AppTextField(
              label: 'ofertas.notes'.tr(),
              controller: _notes,
              minLines: 2,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(
                  _editingId == null ? 'ofertas.add'.tr() : 'ofertas.save'.tr(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
