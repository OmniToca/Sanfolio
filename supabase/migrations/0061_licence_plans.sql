-- Komerční vrstva jako OmniToca Mesa/Servicio/Cadena: 3 balíčky, ne 10 přepínačů.
-- Entitlement zůstává organization_modules + FeatureGate. Plán mapuje included keys.
-- Doplňky (AI, faktury) jdou i na nižší balíček. Sleva licence_discount_bps beze změny.

CREATE TABLE IF NOT EXISTS licence_plans (
  key            TEXT PRIMARY KEY,
  monthly_cents  INT NOT NULL DEFAULT 0 CHECK (monthly_cents >= 0),
  sort_order     INT NOT NULL DEFAULT 100
);

COMMENT ON TABLE licence_plans IS
  'Komerční tarify Carpeta / Despacho / Asesoría. Cena za balíček, ne součet modulů.';

INSERT INTO licence_plans (key, monthly_cents, sort_order) VALUES
  ('carpeta', 0, 10),
  ('despacho', 0, 20),
  ('asesoria', 0, 30)
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS licence_plan_modules (
  plan_key    TEXT NOT NULL REFERENCES licence_plans (key),
  module_key  TEXT NOT NULL REFERENCES modules (key),
  PRIMARY KEY (plan_key, module_key)
);

COMMENT ON TABLE licence_plan_modules IS
  'Included klíče tarifu. Vyšší balíček obsahuje nižší.';

INSERT INTO licence_plan_modules (plan_key, module_key) VALUES
  -- Carpeta = evidence (složka + pošta)
  ('carpeta', 'carpeta_inmueble'),
  ('carpeta', 'messaging'),
  -- Despacho = Carpeta + trámites + AI
  ('despacho', 'carpeta_inmueble'),
  ('despacho', 'messaging'),
  ('despacho', 'impuestos'),
  ('despacho', 'nie_poder'),
  ('despacho', 'policia'),
  ('despacho', 'ayuntamiento'),
  ('despacho', 'testament'),
  ('despacho', 'ofertas'),
  ('despacho', 'ai_copilot'),
  -- Asesoría = Despacho + faktury
  ('asesoria', 'carpeta_inmueble'),
  ('asesoria', 'messaging'),
  ('asesoria', 'impuestos'),
  ('asesoria', 'nie_poder'),
  ('asesoria', 'policia'),
  ('asesoria', 'ayuntamiento'),
  ('asesoria', 'testament'),
  ('asesoria', 'ofertas'),
  ('asesoria', 'ai_copilot'),
  ('asesoria', 'facturacion')
ON CONFLICT DO NOTHING;

ALTER TABLE licence_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE licence_plan_modules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS licence_plans_read ON licence_plans;
CREATE POLICY licence_plans_read ON licence_plans
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS licence_plan_modules_read ON licence_plan_modules;
CREATE POLICY licence_plan_modules_read ON licence_plan_modules
  FOR SELECT TO authenticated USING (true);

ALTER TABLE tenant_settings
  ADD COLUMN IF NOT EXISTS licence_plan_key TEXT NOT NULL DEFAULT 'carpeta'
  REFERENCES licence_plans (key);

COMMENT ON COLUMN tenant_settings.licence_plan_key IS
  'Jeden živý tarif kanceláře. Mění jen Support přes set_office_plan.';

-- Existující kanceláře: heuristika z živých modulů (cadena > servicio > mesa).
UPDATE tenant_settings ts
SET licence_plan_key = CASE
  WHEN EXISTS (
    SELECT 1 FROM organization_modules om
    WHERE om.tenant_id = ts.tenant_id
      AND om.deleted_at IS NULL
      AND om.status IN ('active', 'trial')
      AND om.module_key = 'facturacion'
  ) THEN 'asesoria'
  WHEN EXISTS (
    SELECT 1 FROM organization_modules om
    WHERE om.tenant_id = ts.tenant_id
      AND om.deleted_at IS NULL
      AND om.status IN ('active', 'trial')
      AND om.module_key IN (
        'impuestos', 'nie_poder', 'policia', 'ayuntamiento',
        'testament', 'ofertas', 'ai_copilot'
      )
  ) THEN 'despacho'
  ELSE 'carpeta'
END
WHERE ts.deleted_at IS NULL;

-- Owner nesmí přepsat licenci přes UPDATE tenant_settings.
CREATE OR REPLACE FUNCTION public.protect_licence_settings()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT public.auth_is_support_user() THEN
    NEW.licence_plan_key := OLD.licence_plan_key;
    NEW.licence_discount_bps := OLD.licence_discount_bps;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_licence_settings ON tenant_settings;
CREATE TRIGGER trg_protect_licence_settings
  BEFORE UPDATE ON tenant_settings
  FOR EACH ROW EXECUTE FUNCTION public.protect_licence_settings();

-- Zapne included; vypne služby, které nejsou v balíčku ani živý doplněk.
CREATE OR REPLACE FUNCTION public.sync_office_plan_modules(
  p_tenant_id UUID,
  p_plan_key TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE organization_modules om
  SET deleted_at = now()
  WHERE om.tenant_id = p_tenant_id
    AND om.deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM licence_plan_modules lpm
      WHERE lpm.plan_key = p_plan_key
        AND lpm.module_key = om.module_key
    )
    AND om.module_key NOT IN ('ai_copilot', 'facturacion')
    AND NOT EXISTS (
      SELECT 1 FROM modules m
      WHERE m.key = om.module_key AND m.always_on
    );

  INSERT INTO organization_modules (tenant_id, module_key, status)
  SELECT p_tenant_id, lpm.module_key, 'active'
  FROM licence_plan_modules lpm
  WHERE lpm.plan_key = p_plan_key
    AND NOT EXISTS (
      SELECT 1 FROM organization_modules om
      WHERE om.tenant_id = p_tenant_id
        AND om.module_key = lpm.module_key
        AND om.deleted_at IS NULL
    );
END;
$$;

COMMENT ON FUNCTION public.sync_office_plan_modules(UUID, TEXT) IS
  'Interní: included ON, trámites mimo balíček OFF, živé doplňky zůstanou.';

-- Po heuristice doplnit included, ať TEST/Jarka o nic nepřijdou.
SELECT public.sync_office_plan_modules(ts.tenant_id, ts.licence_plan_key)
FROM tenant_settings ts
WHERE ts.deleted_at IS NULL;

CREATE OR REPLACE FUNCTION public.set_office_plan(
  p_tenant_id UUID,
  p_plan_key TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_tenant_id IS NULL OR p_plan_key IS NULL OR p_plan_key = '' THEN
    RAISE EXCEPTION 'invalid_args';
  END IF;
  IF NOT public.auth_is_support_user() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM licence_plans WHERE key = p_plan_key) THEN
    RAISE EXCEPTION 'unknown_plan';
  END IF;

  UPDATE tenant_settings
  SET licence_plan_key = p_plan_key
  WHERE tenant_id = p_tenant_id
    AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'office_missing';
  END IF;

  PERFORM public.sync_office_plan_modules(p_tenant_id, p_plan_key);

  INSERT INTO audit_logs (
    tenant_id, actor_id, action, entity_table, after
  ) VALUES (
    p_tenant_id,
    auth.uid(),
    'office.plan',
    'tenant_settings',
    jsonb_build_object('licence_plan_key', p_plan_key)
  );

  RETURN p_plan_key;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_office_plan(UUID, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.sync_office_plan_modules(UUID, TEXT)
  FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.set_office_plan(UUID, TEXT) IS
  'Jen Support nastaví tarif kanceláře a synchronizuje organization_modules.';

CREATE OR REPLACE FUNCTION public.set_plan_monthly_cents(
  p_key TEXT,
  p_cents INT
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cents INT;
BEGIN
  IF NOT public.auth_is_support_user() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_key IS NULL OR p_key = '' THEN
    RAISE EXCEPTION 'invalid_args';
  END IF;
  v_cents := GREATEST(0, COALESCE(p_cents, 0));

  UPDATE licence_plans
  SET monthly_cents = v_cents
  WHERE key = p_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown_plan';
  END IF;

  INSERT INTO audit_logs (
    actor_id, action, entity_table, after
  ) VALUES (
    auth.uid(),
    'plan.price',
    'licence_plans',
    jsonb_build_object('key', p_key, 'monthly_cents', v_cents)
  );

  RETURN v_cents;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_plan_monthly_cents(TEXT, INT)
  TO authenticated;

COMMENT ON FUNCTION public.set_plan_monthly_cents(TEXT, INT) IS
  'Ceník balíčku. Cents. Jen Support.';

-- Doplněk jen když není v aktuálním plánu. Included nejde vypnout.
CREATE OR REPLACE FUNCTION public.set_office_module(
  p_tenant_id UUID,
  p_module_key TEXT,
  p_on BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_always BOOLEAN;
  v_plan TEXT;
  v_included BOOLEAN;
  v_addon BOOLEAN;
BEGIN
  IF p_tenant_id IS NULL OR p_module_key IS NULL OR p_module_key = '' THEN
    RAISE EXCEPTION 'invalid_args';
  END IF;
  IF NOT public.auth_is_support_user() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT always_on INTO v_always
  FROM modules
  WHERE key = p_module_key;
  IF v_always IS NULL THEN
    RAISE EXCEPTION 'unknown_module';
  END IF;
  IF v_always OR p_module_key = 'client_portal' THEN
    RAISE EXCEPTION 'module_locked';
  END IF;

  SELECT licence_plan_key INTO v_plan
  FROM tenant_settings
  WHERE tenant_id = p_tenant_id
    AND deleted_at IS NULL;
  IF v_plan IS NULL THEN
    RAISE EXCEPTION 'office_missing';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM licence_plan_modules
    WHERE plan_key = v_plan AND module_key = p_module_key
  ) INTO v_included;
  IF v_included THEN
    RAISE EXCEPTION 'module_in_plan';
  END IF;

  v_addon := p_module_key IN ('ai_copilot', 'facturacion');
  IF NOT v_addon THEN
    RAISE EXCEPTION 'not_addon';
  END IF;

  IF p_on THEN
    IF NOT EXISTS (
      SELECT 1
      FROM organization_modules
      WHERE tenant_id = p_tenant_id
        AND module_key = p_module_key
        AND deleted_at IS NULL
    ) THEN
      INSERT INTO organization_modules (tenant_id, module_key, status)
      VALUES (p_tenant_id, p_module_key, 'active');
    END IF;
  ELSE
    UPDATE organization_modules
    SET deleted_at = now()
    WHERE tenant_id = p_tenant_id
      AND module_key = p_module_key
      AND deleted_at IS NULL;
  END IF;

  INSERT INTO audit_logs (
    tenant_id, actor_id, action, entity_table, after
  ) VALUES (
    p_tenant_id,
    auth.uid(),
    'office.module',
    'organization_modules',
    jsonb_build_object('module_key', p_module_key, 'on', p_on)
  );

  RETURN p_on;
END;
$$;
