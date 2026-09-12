-- Tým kanceláře: max 3 lidé. Asistente nesmí schovat expediente.

CREATE OR REPLACE FUNCTION public.is_tenant_owner(_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM tenant_members tm
    WHERE tm.tenant_id = _tenant_id
      AND tm.profile_id = auth.uid()
      AND tm.role = 'owner'
      AND tm.deleted_at IS NULL
  ) OR (
    public.auth_is_support_user()
    AND public.current_impersonation_tenant() = _tenant_id
  );
$$;

CREATE OR REPLACE FUNCTION public.current_member_role(_tenant_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT tm.role::text
  FROM tenant_members tm
  WHERE tm.tenant_id = _tenant_id
    AND tm.profile_id = auth.uid()
    AND tm.deleted_at IS NULL
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.can_soft_delete_expediente(_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_tenant_owner(_tenant_id)
      OR public.current_member_role(_tenant_id) = 'gestor';
$$;

GRANT EXECUTE ON FUNCTION public.is_tenant_owner(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_member_role(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_soft_delete_expediente(UUID) TO authenticated;

DROP POLICY IF EXISTS tenant_members_modify ON tenant_members;
CREATE POLICY tenant_members_modify ON tenant_members
  FOR INSERT TO authenticated
  WITH CHECK (public.is_tenant_owner(tenant_id));

DROP POLICY IF EXISTS tenant_members_update ON tenant_members;
CREATE POLICY tenant_members_update ON tenant_members
  FOR UPDATE TO authenticated
  USING (public.is_tenant_owner(tenant_id))
  WITH CHECK (public.is_tenant_owner(tenant_id));

DROP POLICY IF EXISTS expedientes_update ON expedientes;
CREATE POLICY expedientes_update ON expedientes
  FOR UPDATE TO authenticated
  USING (public.can_access_tenant(tenant_id))
  WITH CHECK (
    public.can_access_tenant(tenant_id)
    AND (
      deleted_at IS NULL
      OR public.can_soft_delete_expediente(tenant_id)
    )
  );
