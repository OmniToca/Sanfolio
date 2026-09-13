/// Katalog modulů. Nový modul = nový klíč tady + řádek v SQL `modules`.
enum GestoriaModule {
  core,
  carpetaInmueble,
  impuestos,
  niePoder,
  messaging,
  aiCopilot,
  facturacion,
  policia,
  ayuntamiento,
  testament,
  clientPortal,
}

extension GestoriaModuleKey on GestoriaModule {
  String get key => switch (this) {
        GestoriaModule.core => 'core',
        GestoriaModule.carpetaInmueble => 'carpeta_inmueble',
        GestoriaModule.impuestos => 'impuestos',
        GestoriaModule.niePoder => 'nie_poder',
        GestoriaModule.messaging => 'messaging',
        GestoriaModule.aiCopilot => 'ai_copilot',
        GestoriaModule.facturacion => 'facturacion',
        GestoriaModule.policia => 'policia',
        GestoriaModule.ayuntamiento => 'ayuntamiento',
        GestoriaModule.testament => 'testament',
        GestoriaModule.clientPortal => 'client_portal',
      };

  static GestoriaModule? fromKey(String key) {
    for (final m in GestoriaModule.values) {
      if (m.key == key) return m;
    }
    return null;
  }
}

/// Pojmenované díry v shellu. Modul sem přispěje widgetem, neskládá celou stránku.
enum UiSlot { inboxFeed, clienteTabs, carpetaBlocks, settingsSection }
