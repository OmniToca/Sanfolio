-- Kdo platí víc než tarif kanceláře. Čte jen uložené extracted, ne trh. AI neodesílá.

CREATE OR REPLACE FUNCTION public.extracted_cents(p_raw TEXT)
RETURNS INT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  t TEXT := btrim(coalesce(p_raw, ''));
  n NUMERIC;
BEGIN
  IF t = '' THEN
    RETURN NULL;
  END IF;
  IF t ~ '^[0-9]+$' THEN
    RETURN t::INT;
  END IF;
  t := replace(t, E'\u00A0', '');
  t := replace(t, ' ', '');
  IF position(',' in t) > 0 THEN
    t := replace(replace(t, '.', ''), ',', '.');
  END IF;
  n := t::NUMERIC;
  RETURN round(n * 100)::INT;
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.parse_consumption_qty(p_raw TEXT)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  t TEXT := replace(replace(btrim(coalesce(p_raw, '')), E'\u00A0', ''), ' ', '');
  m TEXT;
BEGIN
  IF t = '' THEN
    RETURN NULL;
  END IF;
  m := (regexp_match(t, '([0-9]+(?:[.,][0-9]+)?)'))[1];
  IF m IS NULL THEN
    RETURN NULL;
  END IF;
  IF position(',' in m) > 0 THEN
    m := replace(replace(m, '.', ''), ',', '.');
  END IF;
  RETURN m::NUMERIC;
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.parse_office_date(p_raw TEXT)
RETURNS DATE
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  t TEXT := btrim(coalesce(p_raw, ''));
  parts TEXT[];
BEGIN
  IF t = '' THEN
    RETURN NULL;
  END IF;
  IF t ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}' THEN
    RETURN substring(t from 1 for 10)::DATE;
  END IF;
  parts := regexp_match(t, '^([0-9]{1,2})[./-]([0-9]{1,2})[./-]([0-9]{4})$');
  IF parts IS NOT NULL THEN
    RETURN make_date(parts[3]::INT, parts[2]::INT, parts[1]::INT);
  END IF;
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.overpaying_suministro(p_tenant_id UUID)
RETURNS TABLE (
  cliente_id UUID,
  cliente_nombre TEXT,
  bloque_key TEXT,
  expediente_id UUID,
  client_annual_cents INT,
  offer_id UUID,
  offer_title TEXT,
  offer_annual_cents INT,
  saving_cents INT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  RETURN QUERY
  SELECT
    x.cliente_id,
    x.cliente_nombre,
    x.bloque_key,
    x.expediente_id,
    x.client_annual_cents,
    x.offer_id,
    x.offer_title,
    x.offer_annual_cents,
    x.saving_cents
  FROM (
    SELECT DISTINCT ON (p.cliente_id, p.expediente_id, p.bloque_key)
      p.cliente_id,
      p.cliente_nombre,
      p.bloque_key,
      p.expediente_id,
      p.client_annual AS client_annual_cents,
      o.id AS offer_id,
      o.title AS offer_title,
      oa.offer_annual AS offer_annual_cents,
      (p.client_annual - oa.offer_annual) AS saving_cents
    FROM (
      SELECT
        l.cliente_id,
        l.cliente_nombre,
        l.bloque_key,
        l.expediente_id,
        CASE
          WHEN l.bloque_key = 'seguro' AND (l.period_days IS NULL OR l.period_days <= 0)
            THEN l.amount_cents
          WHEN l.period_days IS NOT NULL AND l.period_days > 0
            THEN round(l.amount_cents * 365.0 / l.period_days)::INT
          ELSE NULL
        END AS client_annual,
        CASE
          WHEN l.qty IS NOT NULL AND l.qty > 0
               AND l.period_days IS NOT NULL AND l.period_days > 0
            THEN l.qty * 365.0 / l.period_days
          WHEN l.qty IS NOT NULL AND l.qty > 0 THEN l.qty
          ELSE NULL
        END AS yearly_qty
      FROM (
        SELECT
          r.cliente_id,
          r.cliente_nombre,
          r.bloque_key,
          r.expediente_id,
          r.amount_cents,
          r.qty,
          CASE
            WHEN r.period_from IS NOT NULL
                 AND r.period_to IS NOT NULL
                 AND r.period_to > r.period_from
              THEN (r.period_to - r.period_from)
            ELSE NULL
          END AS period_days
        FROM (
          SELECT
            c.id AS cliente_id,
            COALESCE(c.nombre, '') AS cliente_nombre,
            b.template_key AS bloque_key,
            b.expediente_id,
            d.tipo,
            public.extracted_cents(d.extracted->>'fields.amount') AS amount_cents,
            public.parse_consumption_qty(d.extracted->>'fields.consumption') AS qty,
            public.parse_office_date(d.extracted->>'fields.periodFrom') AS period_from,
            public.parse_office_date(d.extracted->>'fields.periodTo') AS period_to,
            public.parse_office_date(d.extracted->>'fields.issued') AS issued,
            d.created_at,
            row_number() OVER (
              PARTITION BY c.id, b.expediente_id, b.template_key
              ORDER BY COALESCE(
                public.parse_office_date(d.extracted->>'fields.periodTo'),
                public.parse_office_date(d.extracted->>'fields.issued'),
                public.parse_office_date(d.extracted->>'fields.periodFrom'),
                (d.created_at AT TIME ZONE 'UTC')::date
              ) DESC NULLS LAST
            ) AS rn
          FROM public.bloques b
          JOIN public.expedientes e
            ON e.id = b.expediente_id AND e.deleted_at IS NULL
          JOIN public.clientes c
            ON c.id = e.cliente_id AND c.deleted_at IS NULL
          JOIN public.documentos d
            ON d.bloque_id = b.id
           AND d.deleted_at IS NULL
           AND d.extracted IS NOT NULL
           AND d.extracted <> '{}'::jsonb
          WHERE b.tenant_id = p_tenant_id
            AND b.deleted_at IS NULL
            AND b.status <> 'off'
            AND b.template_key IN ('luz', 'gaz', 'seguro')
            AND (
              (b.template_key IN ('luz', 'gaz')
                AND (d.tipo LIKE 'factura%' OR d.tipo LIKE 'recibo%'))
              OR (b.template_key = 'seguro' AND d.tipo = 'poliza_seguro')
            )
        ) r
        WHERE r.rn = 1
          AND r.amount_cents IS NOT NULL
          AND r.amount_cents > 0
      ) l
    ) p
    JOIN public.office_offers o
      ON o.tenant_id = p_tenant_id
     AND o.deleted_at IS NULL
     AND o.kind = p.bloque_key
    CROSS JOIN LATERAL (
      SELECT CASE
        WHEN o.annual_cents IS NOT NULL THEN o.annual_cents
        WHEN o.unit_cents IS NOT NULL AND p.yearly_qty IS NOT NULL
          THEN round(o.unit_cents * p.yearly_qty)::INT
        ELSE NULL
      END AS offer_annual
    ) oa
    WHERE p.client_annual IS NOT NULL
      AND oa.offer_annual IS NOT NULL
      AND p.client_annual > oa.offer_annual
    ORDER BY
      p.cliente_id,
      p.expediente_id,
      p.bloque_key,
      (p.client_annual - oa.offer_annual) DESC
  ) x
  ORDER BY x.saving_cents DESC, x.cliente_nombre;
END;
$$;

CREATE OR REPLACE FUNCTION public.overpaying_suministro_count(p_tenant_id UUID)
RETURNS INT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_n INT;
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  SELECT COUNT(*)::INT INTO v_n
    FROM public.overpaying_suministro(p_tenant_id);
  RETURN COALESCE(v_n, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.extracted_cents(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.parse_consumption_qty(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.parse_office_date(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.overpaying_suministro(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.overpaying_suministro_count(UUID) TO authenticated;

COMMENT ON FUNCTION public.overpaying_suministro(UUID) IS
  'Klienti, kteří z uložených faktur platí víc než office_offers. AI neodesílá.';
