-- Moduly, nastavení kanceláře, jazyk zpráv.
-- Defaulty zůstávají v bloque_templates / plazo_rules; kancelář přepisuje tady.

CREATE TABLE modules (
  key          TEXT PRIMARY KEY,
  label_i18n   JSONB NOT NULL DEFAULT '{}',
  always_on    BOOLEAN NOT NULL DEFAULT false,
  sort_order   INT NOT NULL DEFAULT 100
);

INSERT INTO modules (key, label_i18n, always_on, sort_order) VALUES
  ('core', '{"cs":"Základ","en":"Core","es":"Núcleo"}', true, 0),
  ('carpeta_inmueble', '{"cs":"Složka nemovitosti","en":"Property file","es":"Carpeta inmueble"}', false, 10),
  ('impuestos', '{"cs":"Daně","en":"Taxes","es":"Impuestos"}', false, 20),
  ('nie_poder', '{"cs":"NIE a plná moc","en":"NIE and power of attorney","es":"NIE y poder"}', false, 30),
  ('messaging', '{"cs":"Zprávy","en":"Messaging","es":"Mensajes"}', false, 40),
  ('ai_copilot', '{"cs":"AI asistent","en":"AI copilot","es":"Copiloto IA"}', false, 50),
  ('client_portal', '{"cs":"Zóna klienta","en":"Client zone","es":"Zona cliente"}', false, 90);

CREATE TABLE organization_modules (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    UUID NOT NULL REFERENCES tenants (id),
  module_key   TEXT NOT NULL REFERENCES modules (key),
  status       TEXT NOT NULL DEFAULT 'active'
               CHECK (status IN ('trial', 'active', 'cancelled', 'past_due')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at   TIMESTAMPTZ
);

CREATE UNIQUE INDEX uq_org_modules_live
  ON organization_modules (tenant_id, module_key)
  WHERE deleted_at IS NULL;

CREATE TABLE tenant_settings (
  tenant_id               UUID PRIMARY KEY REFERENCES tenants (id),
  staff_locale            TEXT NOT NULL DEFAULT 'cs',
  default_client_locale   TEXT NOT NULL DEFAULT 'cs',
  plusvalia_days          INT NOT NULL DEFAULT 30,
  nudge_interval_days     INT NOT NULL DEFAULT 7,
  plazo_offsets           JSONB NOT NULL DEFAULT '{}',
  slot_order              JSONB NOT NULL DEFAULT '{}',
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at              TIMESTAMPTZ
);

ALTER TABLE clientes
  RENAME COLUMN idioma TO locale;

ALTER TABLE clientes
  ALTER COLUMN locale SET DEFAULT 'cs';

COMMENT ON COLUMN clientes.locale IS 'Jazyk komunikace s klientem (cs/en/de/fr/es). Překlady zpráv cílí sem.';

ALTER TABLE profiles
  ADD COLUMN locale TEXT NOT NULL DEFAULT 'cs';

ALTER TABLE mensajes
  ADD COLUMN locale_original TEXT NOT NULL DEFAULT 'cs',
  ADD COLUMN translations JSONB NOT NULL DEFAULT '{}';

COMMENT ON COLUMN mensajes.translations IS 'Mapa locale → text. Klientská zóna ukáže originál (cuerpo) + translations[cliente.locale].';

ALTER TABLE modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY modules_read ON modules FOR SELECT TO authenticated USING (true);

CREATE POLICY org_modules_all ON organization_modules
  FOR ALL TO authenticated
  USING (public.can_access_tenant(tenant_id))
  WITH CHECK (public.can_access_tenant(tenant_id));

CREATE POLICY tenant_settings_all ON tenant_settings
  FOR ALL TO authenticated
  USING (public.can_access_tenant(tenant_id))
  WITH CHECK (public.can_access_tenant(tenant_id));

CREATE TRIGGER trg_organization_modules_updated
  BEFORE UPDATE ON organization_modules
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_tenant_settings_updated
  BEFORE UPDATE ON tenant_settings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_organization_modules_no_hard_delete
  BEFORE DELETE ON organization_modules
  FOR EACH ROW EXECUTE FUNCTION forbid_hard_delete();

CREATE TRIGGER trg_tenant_settings_no_hard_delete
  BEFORE DELETE ON tenant_settings
  FOR EACH ROW EXECUTE FUNCTION forbid_hard_delete();
