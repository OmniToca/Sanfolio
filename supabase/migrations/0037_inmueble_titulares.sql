-- Spoluvlastníci finca. Složka = inmuebles.cliente_id. Kontakty = client_contacts.
-- 210 čte sharePercent z řádku titulare, ne z karty.

CREATE TABLE public.inmueble_titulares (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        UUID NOT NULL REFERENCES tenants (id),
  inmueble_id      UUID NOT NULL REFERENCES inmuebles (id),
  lado             TEXT NOT NULL CHECK (lado IN ('comprador', 'vendedor')),
  derecho          TEXT NOT NULL DEFAULT 'pleno_dominio',
  nombre           TEXT NOT NULL,
  nie_raw          TEXT NOT NULL DEFAULT '',
  nie_normalized   TEXT NOT NULL DEFAULT '',
  cuota_bps        INT NOT NULL CHECK (cuota_bps >= 1 AND cuota_bps <= 10000),
  cliente_id       UUID REFERENCES clientes (id),
  desde            DATE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at       TIMESTAMPTZ
);

CREATE INDEX idx_inmueble_titulares_inmueble
  ON inmueble_titulares (inmueble_id)
  WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_inmueble_titulares_nie_live
  ON inmueble_titulares (inmueble_id, nie_normalized)
  WHERE deleted_at IS NULL AND nie_normalized <> '';

CREATE INDEX idx_inmueble_titulares_cliente
  ON inmueble_titulares (cliente_id)
  WHERE deleted_at IS NULL AND cliente_id IS NOT NULL;

ALTER TABLE inmueble_titulares ENABLE ROW LEVEL SECURITY;

CREATE POLICY inmueble_titulares_select ON inmueble_titulares
  FOR SELECT TO authenticated USING (public.can_access_tenant(tenant_id));
CREATE POLICY inmueble_titulares_insert ON inmueble_titulares
  FOR INSERT TO authenticated WITH CHECK (public.can_access_tenant(tenant_id));
CREATE POLICY inmueble_titulares_update ON inmueble_titulares
  FOR UPDATE TO authenticated
  USING (public.can_access_tenant(tenant_id))
  WITH CHECK (public.can_access_tenant(tenant_id));

CREATE TRIGGER trg_inmueble_titulares_updated
  BEFORE UPDATE ON inmueble_titulares
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_inmueble_titulares_no_hard_delete
  BEFORE DELETE ON inmueble_titulares
  FOR EACH ROW EXECUTE FUNCTION forbid_hard_delete();

CREATE TRIGGER trg_inmueble_titulares_audit
  AFTER INSERT OR UPDATE ON inmueble_titulares
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_row_change();

GRANT SELECT, INSERT, UPDATE ON TABLE public.inmueble_titulares TO authenticated;

COMMENT ON TABLE public.inmueble_titulares IS
  'Podíl na finca. inmuebles.cliente_id je složka kanceláře, ne jediný vlastník.';

-- Stopa na kartě složky (Petr vidí Moniku jako titular, ne jako kontakt).
CREATE OR REPLACE FUNCTION public.cliente_audit_log(p_cliente_id UUID)
RETURNS TABLE (
  id UUID,
  created_at TIMESTAMPTZ,
  action TEXT,
  entity_table TEXT,
  actor_name TEXT,
  actor_email TEXT,
  impersonating BOOLEAN,
  detail JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
BEGIN
  SELECT c.tenant_id INTO v_tenant
  FROM clientes c
  WHERE c.id = p_cliente_id;
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.is_tenant_owner(v_tenant) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN QUERY
  SELECT
    a.id,
    a.created_at,
    a.action,
    a.entity_table,
    coalesce(nullif(btrim(p.full_name), ''), p.email)::TEXT,
    p.email,
    (a.impersonation_session_id IS NOT NULL),
    CASE
      WHEN a.entity_table = 'documentos' THEN
        jsonb_strip_nulls(jsonb_build_object(
          'tipo', nullif(coalesce(a.after->>'tipo', d.tipo), ''),
          'original_name', nullif(
            coalesce(a.after->>'original_name', d.original_name),
            ''
          )
        ))
      WHEN a.entity_table = 'mensajes' THEN
        jsonb_strip_nulls(jsonb_build_object(
          'asunto', nullif(a.after->>'asunto', '')
        ))
      WHEN a.entity_table = 'client_contacts' THEN
        jsonb_strip_nulls(jsonb_build_object(
          'nombre', nullif(a.after->>'nombre', ''),
          'relacion', nullif(a.after->>'relacion', '')
        ))
      WHEN a.entity_table = 'inmueble_titulares' THEN
        jsonb_strip_nulls(jsonb_build_object(
          'nombre', nullif(a.after->>'nombre', ''),
          'lado', nullif(a.after->>'lado', ''),
          'cuota_bps', a.after->'cuota_bps'
        ))
      WHEN a.entity_table = 'clientes' THEN
        jsonb_strip_nulls(jsonb_build_object(
          'surface', nullif(a.after->>'surface', ''),
          'changed', (
            SELECT jsonb_agg(x.key ORDER BY x.key)
            FROM jsonb_each(coalesce(a.after, '{}'::jsonb)) x
            WHERE a.before IS NOT NULL
              AND x.key NOT IN (
                'id', 'tenant_id', 'created_at', 'updated_at', 'deleted_at',
                'created_by', 'search_vector'
              )
              AND (a.before -> x.key) IS DISTINCT FROM x.value
          )
        ))
      ELSE '{}'::jsonb
    END
  FROM audit_logs a
  LEFT JOIN profiles p ON p.id = a.actor_id
  LEFT JOIN documentos d
    ON d.id = a.entity_id AND a.entity_table = 'documentos'
  WHERE a.tenant_id = v_tenant
    AND (
      (a.entity_table = 'clientes' AND a.entity_id = p_cliente_id)
      OR (
        a.entity_table = 'mensajes'
        AND EXISTS (
          SELECT 1 FROM mensajes m
          WHERE m.id = a.entity_id AND m.cliente_id = p_cliente_id
        )
      )
      OR (
        a.entity_table = 'documentos'
        AND EXISTS (
          SELECT 1 FROM documentos dx
          WHERE dx.id = a.entity_id AND dx.cliente_id = p_cliente_id
        )
      )
      OR (
        a.entity_table = 'client_contacts'
        AND EXISTS (
          SELECT 1 FROM client_contacts cc
          WHERE cc.id = a.entity_id AND cc.cliente_id = p_cliente_id
        )
      )
      OR (
        a.entity_table = 'inmueble_titulares'
        AND EXISTS (
          SELECT 1
          FROM inmueble_titulares t
          JOIN inmuebles i ON i.id = t.inmueble_id AND i.deleted_at IS NULL
          WHERE t.id = a.entity_id
            AND i.cliente_id = p_cliente_id
        )
      )
    )
  ORDER BY a.created_at DESC
  LIMIT 50;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cliente_audit_log(UUID) TO authenticated;

COMMENT ON FUNCTION public.cliente_audit_log(UUID) IS
  'LOPDGDD stopa karty. Titulares přes inmueble složky, ne jako kontakt. Jen owner.';
