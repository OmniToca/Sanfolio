import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';

/// Pojmenované sekce Nastavení. Rail zůstává pět položek; nová agenda = odrážka tady.
///
/// PROČ: dřív Tab „Kancelář“ míchal tenant (licence, Pošta, faktury) s osobním
/// účtem (heslo, staff locale). Petr chce čistou IA bez další ikony v railu.
enum SettingsSectionId {
  office,
  account,
  team,
  deadlines,
  folder,
  posta,
  facturacion,
  ofertas,
}

extension SettingsSectionIdX on SettingsSectionId {
  String get routeKey => name;

  String get labelKey => switch (this) {
        SettingsSectionId.office => 'settings.sectionOffice',
        SettingsSectionId.account => 'settings.sectionAccount',
        SettingsSectionId.team => 'settings.sectionTeam',
        SettingsSectionId.deadlines => 'settings.sectionDeadlines',
        SettingsSectionId.folder => 'settings.sectionFolder',
        SettingsSectionId.posta => 'settings.sectionPosta',
        SettingsSectionId.facturacion => 'settings.sectionFacturacion',
        SettingsSectionId.ofertas => 'settings.sectionOfertas',
      };

  GestoriaModule? get requiredModule => switch (this) {
        SettingsSectionId.posta => GestoriaModule.messaging,
        SettingsSectionId.facturacion => GestoriaModule.facturacion,
        SettingsSectionId.ofertas => GestoriaModule.ofertas,
        _ => null,
      };
}

SettingsSectionId? parseSettingsSection(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  for (final id in SettingsSectionId.values) {
    if (id.routeKey == raw) return id;
  }
  return null;
}

/// Viditelné odrážky podle licence. Core sekce jsou vždy.
List<SettingsSectionId> visibleSettingsSections(TenantConfig? cfg) {
  return [
    for (final id in SettingsSectionId.values)
      if (id.requiredModule == null || (cfg?.isOn(id.requiredModule!) ?? false))
        id,
  ];
}
