import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../settings/office_settings_controller.dart';

/// Slot `settings.section`. NIF emisoru pro pozdější Emitir, ne SIF v jádru.
class FacturacionSettingsSection extends ConsumerStatefulWidget {
  const FacturacionSettingsSection({super.key, required this.settings});

  final OfficeSettings settings;

  @override
  ConsumerState<FacturacionSettingsSection> createState() =>
      _FacturacionSettingsSectionState();
}

class _FacturacionSettingsSectionState
    extends ConsumerState<FacturacionSettingsSection> {
  late final TextEditingController _nif;
  late final TextEditingController _nombre;
  late final TextEditingController _serie;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _nif = TextEditingController(text: widget.settings.emisorNif);
    _nombre = TextEditingController(text: widget.settings.emisorNombre);
    _serie = TextEditingController(text: widget.settings.facturaSerie);
  }

  @override
  void didUpdateWidget(covariant FacturacionSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.emisorNif != widget.settings.emisorNif &&
        _nif.text != widget.settings.emisorNif) {
      _nif.text = widget.settings.emisorNif;
    }
    if (oldWidget.settings.emisorNombre != widget.settings.emisorNombre &&
        _nombre.text != widget.settings.emisorNombre) {
      _nombre.text = widget.settings.emisorNombre;
    }
    if (oldWidget.settings.facturaSerie != widget.settings.facturaSerie &&
        _serie.text != widget.settings.facturaSerie) {
      _serie.text = widget.settings.facturaSerie;
    }
  }

  @override
  void dispose() {
    _nif.dispose();
    _nombre.dispose();
    _serie.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _later(void Function() fn) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), fn);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.read(officeSettingsProvider.notifier);
    return FeatureGate(
      module: GestoriaModule.facturacion,
      child: AppSectionCard(
        title: 'facturacion.settingsTitle'.tr(),
        hint: 'facturacion.settingsHint'.tr(),
        child: Column(
          children: [
            AppTextField(
              label: 'facturacion.emisorNif'.tr(),
              controller: _nif,
              onChanged: (v) => _later(() => ctrl.setEmisorNif(v)),
            ),
            const SizedBox(height: 8),
            AppTextField(
              label: 'facturacion.emisorNombre'.tr(),
              controller: _nombre,
              onChanged: (v) => _later(() => ctrl.setEmisorNombre(v)),
            ),
            const SizedBox(height: 8),
            AppTextField(
              label: 'facturacion.serie'.tr(),
              controller: _serie,
              onChanged: (v) => _later(() => ctrl.setFacturaSerie(v)),
            ),
          ],
        ),
      ),
    );
  }
}
