-- Rozsah týmu: bez stropu počtu lidí. Owner vidí vše.
-- Ostatní můžou být scoped: jen přiřazené karty a volitelně jen některé bloky.
-- AI sem nesahá.

CREATE TABLE public.staff_scopes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants (id),
  profile_id UUID NOT NULL REFERENCES public.profiles (id),
  scoped BOOLEAN NOT NULL DEFAULT false,
  bloque_keys TEXT[] NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX uq_staff_scopes_live
  ON public.staff_scopes (tenant_id, profile_id)
  WHERE deleted_at IS NULL;

CREATE TABLE public.staff_cliente_access (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES public.tenants (id),
  profile_id UUID NOT NULL REFERENCES public.profiles (id),
  cliente_id UUID NOT NULL REFERENCES public.clientes (id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX uq_staff_cliente_access_live
  ON public.staff_cliente_access (tenant_id, profile_id, cliente_id)
  WHERE deleted_at IS NULL;

ALTER TABLE public.staff_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_cliente_access ENABLE ROW LEVEL SECURITY;

CREATE POLICY staff_scopes_select ON public.staff_scopes
  FOR SELECT TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND (
      public.is_tenant_owner(tenant_id)
      OR profile_id = auth.uid()
    )
  );

CREATE POLICY staff_scopes_modify ON public.staff_scopes
  FOR ALL TO authenticated
  USING (public.is_tenant_owner(tenant_id))
  WITH CHECK (public.is_tenant_owner(tenant_id));

CREATE POLICY staff_cliente_access_select ON public.staff_cliente_access
  FOR SELECT TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND (
      public.is_tenant_owner(tenant_id)
      OR profile_id = auth.uid()
    )
  );

CREATE POLICY staff_cliente_access_modify ON public.staff_cliente_access
  FOR ALL TO authenticated
  USING (public.is_tenant_owner(tenant_id))
  WITH CHECK (public.is_tenant_owner(tenant_id));

CREATE OR REPLACE FUNCTION public.staff_is_scoped(_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN public.is_tenant_owner(_tenant_id) THEN false
    ELSE coalesce((
      SELECT s.scoped
        FROM public.staff_scopes s
       WHERE s.tenant_id = _tenant_id
         AND s.profile_id = auth.uid()
         AND s.deleted_at IS NULL
       LIMIT 1
    ), false)
  END;
$$;

CREATE OR REPLACE FUNCTION public.can_access_cliente(_cliente_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.clientes c
     WHERE c.id = _cliente_id
       AND public.can_access_tenant(c.tenant_id)
       AND (
         public.is_tenant_owner(c.tenant_id)
         OR NOT public.staff_is_scoped(c.tenant_id)
         OR EXISTS (
           SELECT 1
             FROM public.staff_cliente_access a
            WHERE a.tenant_id = c.tenant_id
              AND a.profile_id = auth.uid()
              AND a.cliente_id = c.id
              AND a.deleted_at IS NULL
         )
       )
  );
$$;

CREATE OR REPLACE FUNCTION public.can_use_bloque_template(
  _cliente_id UUID,
  _template_key TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.can_access_cliente(_cliente_id)
    AND (
      public.is_tenant_owner((
        SELECT c.tenant_id FROM public.clientes c WHERE c.id = _cliente_id
      ))
      OR NOT public.staff_is_scoped((
        SELECT c.tenant_id FROM public.clientes c WHERE c.id = _cliente_id
      ))
      OR coalesce(_template_key, '') = 'cliente_snapshot'
      OR coalesce((
        SELECT cardinality(s.bloque_keys)
          FROM public.staff_scopes s
          JOIN public.clientes c ON c.tenant_id = s.tenant_id
         WHERE c.id = _cliente_id
           AND s.profile_id = auth.uid()
           AND s.deleted_at IS NULL
         LIMIT 1
      ), 0) = 0
      OR EXISTS (
        SELECT 1
          FROM public.staff_scopes s
          JOIN public.clientes c ON c.tenant_id = s.tenant_id
         WHERE c.id = _cliente_id
           AND s.profile_id = auth.uid()
           AND s.deleted_at IS NULL
           AND _template_key = ANY (s.bloque_keys)
      )
    );
$$;

GRANT EXECUTE ON FUNCTION public.staff_is_scoped(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_cliente(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_use_bloque_template(UUID, TEXT) TO authenticated;

DROP POLICY IF EXISTS clientes_select ON public.clientes;
CREATE POLICY clientes_select ON public.clientes
  FOR SELECT TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND public.can_access_cliente(id)
  );

DROP POLICY IF EXISTS documentos_select ON public.documentos;
CREATE POLICY documentos_select ON public.documentos
  FOR SELECT TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND public.can_access_cliente(cliente_id)
  );

DROP POLICY IF EXISTS expedientes_select ON public.expedientes;
CREATE POLICY expedientes_select ON public.expedientes
  FOR SELECT TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND public.can_access_cliente(cliente_id)
  );

DROP POLICY IF EXISTS bloques_select ON public.bloques;
CREATE POLICY bloques_select ON public.bloques
  FOR SELECT TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND EXISTS (
      SELECT 1
        FROM public.expedientes e
       WHERE e.id = bloques.expediente_id
         AND public.can_access_cliente(e.cliente_id)
         AND public.can_use_bloque_template(e.cliente_id, bloques.template_key)
    )
  );

CREATE OR REPLACE FUNCTION public.staff_scope_set(
  p_profile_id UUID,
  p_scoped BOOLEAN,
  p_bloque_keys TEXT[],
  p_cliente_ids UUID[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
  v_role TEXT;
BEGIN
  SELECT tm.tenant_id, tm.role::text
    INTO v_tenant, v_role
    FROM public.tenant_members tm
   WHERE tm.profile_id = p_profile_id
     AND tm.deleted_at IS NULL
     AND public.is_tenant_owner(tm.tenant_id)
   LIMIT 1;
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF v_role = 'owner' THEN
    RAISE EXCEPTION 'owner_unscoped';
  END IF;

  UPDATE public.staff_scopes
     SET deleted_at = now()
   WHERE tenant_id = v_tenant
     AND profile_id = p_profile_id
     AND deleted_at IS NULL;

  INSERT INTO public.staff_scopes (
    tenant_id, profile_id, scoped, bloque_keys
  ) VALUES (
    v_tenant,
    p_profile_id,
    coalesce(p_scoped, false),
    coalesce(p_bloque_keys, '{}')
  );

  UPDATE public.staff_cliente_access
     SET deleted_at = now()
   WHERE tenant_id = v_tenant
     AND profile_id = p_profile_id
     AND deleted_at IS NULL;

  IF coalesce(p_scoped, false) AND p_cliente_ids IS NOT NULL THEN
    INSERT INTO public.staff_cliente_access (
      tenant_id, profile_id, cliente_id
    )
    SELECT v_tenant, p_profile_id, x
      FROM unnest(p_cliente_ids) AS x
     WHERE EXISTS (
       SELECT 1 FROM public.clientes c
        WHERE c.id = x AND c.tenant_id = v_tenant AND c.deleted_at IS NULL
     );
  END IF;

  INSERT INTO public.audit_logs (
    tenant_id, actor_id, action, entity_table, entity_id, after
  ) VALUES (
    v_tenant,
    auth.uid(),
    'staff.scope',
    'staff_scopes',
    p_profile_id,
    jsonb_build_object(
      'scoped', coalesce(p_scoped, false),
      'bloque_keys', coalesce(p_bloque_keys, '{}'),
      'cliente_ids', coalesce(p_cliente_ids, '{}')
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.staff_scope_set(UUID, BOOLEAN, TEXT[], UUID[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.search_clients(p_q TEXT, p_limit INT DEFAULT 20)
RETURNS TABLE (
  cliente_id UUID,
  score INT,
  matched_via TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, extensions
AS $$
#variable_conflict use_column
DECLARE
  q TEXT := public.normalize_id(p_q);
BEGIN
  IF q IS NULL OR btrim(q) = '' THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH id_hits AS (
    SELECT
      ci.cliente_id AS hit_id,
      CASE
        WHEN ci.value_normalized = q THEN 100
        WHEN public.id_mask_match(ci.value_normalized, q) THEN 90
        WHEN starts_with(ci.value_normalized, q) THEN 80
        WHEN char_length(q) >= 3 AND ci.value_normalized % q THEN 60
        ELSE 0
      END AS hit_score,
      CASE
        WHEN ci.value_normalized = q THEN 'id_exact'::TEXT
        WHEN public.id_mask_match(ci.value_normalized, q) THEN 'id_mask'
        WHEN starts_with(ci.value_normalized, q) THEN 'id_prefix'
        ELSE 'id_trgm'
      END AS hit_via
    FROM client_identifiers ci
    WHERE ci.deleted_at IS NULL
      AND public.can_access_tenant(ci.tenant_id)
      AND public.can_access_cliente(ci.cliente_id)
      AND (
        ci.value_normalized = q
        OR public.id_mask_match(ci.value_normalized, q)
        OR starts_with(ci.value_normalized, q)
        OR (char_length(q) >= 3 AND ci.value_normalized % q)
      )
  ),
  fts_hits AS (
    SELECT
      c.id AS hit_id,
      40 AS hit_score,
      'fts'::TEXT AS hit_via
    FROM clientes c
    WHERE c.deleted_at IS NULL
      AND public.can_access_tenant(c.tenant_id)
      AND public.can_access_cliente(c.id)
      AND char_length(btrim(coalesce(p_q, ''))) >= 2
      AND c.search_vector @@ plainto_tsquery('simple', coalesce(p_q, ''))
  ),
  name_hits AS (
    SELECT
      c.id AS hit_id,
      50 AS hit_score,
      'name'::TEXT AS hit_via
    FROM clientes c
    WHERE c.deleted_at IS NULL
      AND public.can_access_tenant(c.tenant_id)
      AND public.can_access_cliente(c.id)
      AND (
        strpos(upper(coalesce(c.nombre, '')), q) > 0
        OR strpos(upper(coalesce(c.apellidos, '')), q) > 0
        OR strpos(upper(coalesce(c.tel, '')), q) > 0
        OR strpos(upper(coalesce(c.email, '')), q) > 0
      )
  ),
  combined AS (
    SELECT hit_id, hit_score, hit_via FROM id_hits WHERE hit_score > 0
    UNION ALL
    SELECT hit_id, hit_score, hit_via FROM fts_hits
    UNION ALL
    SELECT hit_id, hit_score, hit_via FROM name_hits
  )
  SELECT
    combined.hit_id,
    max(combined.hit_score)::INT,
    (array_agg(combined.hit_via ORDER BY combined.hit_score DESC))[1]
  FROM combined
  GROUP BY combined.hit_id
  ORDER BY max(combined.hit_score) DESC
  LIMIT greatest(1, least(coalesce(p_limit, 20), 50));
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_clients(TEXT, INT) TO authenticated;

COMMENT ON FUNCTION public.can_access_cliente(UUID) IS
  'Owner a nescopovaný člen vidí všechny karty tenantu. Scoped jen přiřazené.';
COMMENT ON FUNCTION public.staff_scope_set(UUID, BOOLEAN, TEXT[], UUID[]) IS
  'Owner nastaví rozsah člena. Ownera omezit nelze.';
