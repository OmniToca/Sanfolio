-- H2: support_view_sessions jen SELECT z klienta; mutate výhradně přes RPC.
-- Soft-delete historie: forbid_hard_delete. Impersonace: reason min. 12 znaků.

DROP POLICY IF EXISTS support_sessions_support ON public.support_view_sessions;

CREATE POLICY support_sessions_select ON public.support_view_sessions
  FOR SELECT TO authenticated
  USING (public.auth_is_support_user());

-- Žádný INSERT/UPDATE/DELETE policy pro authenticated — jen DEFINER RPC.

DROP TRIGGER IF EXISTS trg_support_view_sessions_no_hard_delete
  ON public.support_view_sessions;
CREATE TRIGGER trg_support_view_sessions_no_hard_delete
  BEFORE DELETE ON public.support_view_sessions
  FOR EACH ROW
  EXECUTE FUNCTION public.forbid_hard_delete();

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
  -- Proč: krátký „x“ obchází auditní smysl reason; min. 12 znaků.
  IF char_length(v_reason) < 12 THEN
    RAISE EXCEPTION 'start_impersonation: reason too short'
      USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM tenants t
    WHERE t.id = p_tenant_id AND t.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'start_impersonation: tenant not found' USING ERRCODE = '22023';
  END IF;

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

  INSERT INTO audit_logs (
    tenant_id, actor_id, impersonation_session_id, action, entity_table, entity_id
  ) VALUES (
    p_tenant_id, auth.uid(), v_id, 'impersonation.start', 'tenants', p_tenant_id
  );

  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.start_impersonation(UUID, TEXT, TEXT) IS
  'Support impersonace: reason ≥ 12 znaků; session jen přes tuto RPC.';
