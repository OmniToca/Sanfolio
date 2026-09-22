-- Licence jako OmniToca: ceník na katalogu, zapnuté služby = měsíční
-- poplatek, sleva na kancelář. Zapíná jen Support, ne owner.
-- Vypnutí služby = soft-delete (status cancelled by zamykal celou appku).

ALTER TABLE modules
  ADD COLUMN IF NOT EXISTS monthly_cents INT NOT NULL DEFAULT 0
  CHECK (monthly_cents >= 0);

COMMENT ON COLUMN modules.monthly_cents IS
  'Měsíční ceník v cents. 0 = zatím nevyplněno / zdarma. Support mění v HQ.';

ALTER TABLE tenant_settings
  ADD COLUMN IF NOT EXISTS licence_discount_bps INT NOT NULL DEFAULT 0
  CHECK (licence_discount_bps >= 0 AND licence_discount_bps <= 10000);

COMMENT ON COLUMN tenant_settings.licence_discount_bps IS
  'Sleva kanceláře v basis points (1000 = 10 %, 10000 = 100 %). Nastavuje Support.';

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

GRANT EXECUTE ON FUNCTION public.set_office_module(UUID, TEXT, BOOLEAN)
  TO authenticated;

COMMENT ON FUNCTION public.set_office_module(UUID, TEXT, BOOLEAN) IS
  'Jen Support zapne/vypne placenou službu kanceláře. Soft-delete, ne cancelled.';

CREATE OR REPLACE FUNCTION public.set_office_discount(
  p_tenant_id UUID,
  p_discount_bps INT
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_bps INT;
BEGIN
  IF NOT public.auth_is_support_user() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_tenant_id IS NULL THEN
    RAISE EXCEPTION 'invalid_args';
  END IF;
  v_bps := GREATEST(0, LEAST(10000, COALESCE(p_discount_bps, 0)));

  UPDATE tenant_settings
  SET licence_discount_bps = v_bps
  WHERE tenant_id = p_tenant_id
    AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'office_missing';
  END IF;

  INSERT INTO audit_logs (
    tenant_id, actor_id, action, entity_table, after
  ) VALUES (
    p_tenant_id,
    auth.uid(),
    'office.discount',
    'tenant_settings',
    jsonb_build_object('licence_discount_bps', v_bps)
  );

  RETURN v_bps;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_office_discount(UUID, INT) TO authenticated;

COMMENT ON FUNCTION public.set_office_discount(UUID, INT) IS
  'Jen Support nastaví slevu kanceláře (bps). 10000 = měsíc zdarma.';

CREATE OR REPLACE FUNCTION public.set_module_monthly_cents(
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

  UPDATE modules
  SET monthly_cents = v_cents
  WHERE key = p_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown_module';
  END IF;

  INSERT INTO audit_logs (
    actor_id, action, entity_table, after
  ) VALUES (
    auth.uid(),
    'module.price',
    'modules',
    jsonb_build_object('key', p_key, 'monthly_cents', v_cents)
  );

  RETURN v_cents;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_module_monthly_cents(TEXT, INT)
  TO authenticated;

COMMENT ON FUNCTION public.set_module_monthly_cents(TEXT, INT) IS
  'Ceník katalogu. Cents. Jen Support.';

DROP POLICY IF EXISTS org_modules_support_write ON organization_modules;
CREATE POLICY org_modules_support_write ON organization_modules
  FOR ALL TO authenticated
  USING (public.auth_is_support_user())
  WITH CHECK (public.auth_is_support_user());
