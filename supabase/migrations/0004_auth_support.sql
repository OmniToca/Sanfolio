-- Auth, Support onboarding, impersonace. Založení tenanta jen service_role (Edge).

CREATE OR REPLACE FUNCTION public.start_impersonation(
  p_tenant_id UUID,
  p_reason TEXT,
  p_note TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reason TEXT := trim(coalesce(p_reason, ''));
  v_id UUID;
BEGIN
  IF NOT public.auth_is_support_user() THEN
    RAISE EXCEPTION 'start_impersonation: forbidden' USING ERRCODE = '42501';
  END IF;
  IF v_reason = '' THEN
    RAISE EXCEPTION 'start_impersonation: reason required' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM tenants t
    WHERE t.id = p_tenant_id AND t.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'start_impersonation: tenant not found' USING ERRCODE = '22023';
  END IF;

  -- Jedna živá session na support uživatele.
  UPDATE support_view_sessions
     SET ended_at = now()
   WHERE support_user_id = auth.uid()
     AND ended_at IS NULL;

  INSERT INTO support_view_sessions (
    support_user_id, tenant_id, access_reason, access_note, expires_at
  ) VALUES (
    auth.uid(), p_tenant_id, v_reason, nullif(trim(coalesce(p_note, '')), ''),
    now() + interval '8 hours'
  )
  RETURNING id INTO v_id;

  INSERT INTO audit_logs (tenant_id, actor_id, impersonation_session_id, action, entity_table, entity_id)
  VALUES (p_tenant_id, auth.uid(), v_id, 'impersonation.start', 'tenants', p_tenant_id);

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.end_impersonation(p_session_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.auth_is_support_user() THEN
    RAISE EXCEPTION 'end_impersonation: forbidden' USING ERRCODE = '42501';
  END IF;

  UPDATE support_view_sessions
     SET ended_at = now()
   WHERE id = p_session_id
     AND support_user_id = auth.uid()
     AND ended_at IS NULL;

  INSERT INTO audit_logs (tenant_id, actor_id, impersonation_session_id, action, entity_table, entity_id)
  SELECT s.tenant_id, auth.uid(), s.id, 'impersonation.end', 'tenants', s.tenant_id
    FROM support_view_sessions s
   WHERE s.id = p_session_id
     AND s.support_user_id = auth.uid();
END;
$$;

CREATE OR REPLACE FUNCTION public.current_impersonation()
RETURNS TABLE (
  session_id UUID,
  tenant_id UUID,
  tenant_name TEXT,
  display_name TEXT,
  access_reason TEXT,
  expires_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    s.id,
    s.tenant_id,
    t.name,
    coalesce(ts.display_name, t.name),
    s.access_reason,
    s.expires_at
  FROM support_view_sessions s
  JOIN tenants t ON t.id = s.tenant_id
  LEFT JOIN tenant_settings ts ON ts.tenant_id = t.id
  WHERE s.support_user_id = auth.uid()
    AND s.ended_at IS NULL
    AND s.expires_at > now()
  ORDER BY s.started_at DESC
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.auth_is_support_user() TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_impersonation(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.end_impersonation(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_impersonation() TO authenticated;

-- Support vidí nastavení a licence bez impersonace (žádní klienti).
CREATE POLICY tenant_settings_support_select ON tenant_settings
  FOR SELECT TO authenticated
  USING (public.auth_is_support_user());

CREATE POLICY org_modules_support_select ON organization_modules
  FOR SELECT TO authenticated
  USING (public.auth_is_support_user());
