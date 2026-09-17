-- Kampaň expirací: DNI / pas / poder / seguro v okně z tenant_settings.
-- Chip na kartě už bere poder_warn_days. Tady je office-wide seznam. AI neodesílá.

CREATE OR REPLACE FUNCTION public.expiring_items(p_tenant_id UUID)
RETURNS TABLE (
  cliente_id UUID,
  cliente_nombre TEXT,
  kind TEXT,
  expires_on DATE,
  tone TEXT,
  bloque_id UUID,
  expediente_id UUID,
  documento_id UUID,
  has_email BOOLEAN,
  has_tel BOOLEAN,
  last_requested_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today DATE := (timezone('Europe/Madrid', now()))::date;
  v_poder INT := 60;
  v_seguro INT := 60;
  v_nie BOOLEAN := FALSE;
  v_carpeta BOOLEAN := FALSE;
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT
    coalesce(ts.poder_warn_days, 60),
    coalesce(ts.seguro_warn_days, 60)
  INTO v_poder, v_seguro
  FROM tenant_settings ts
  WHERE ts.tenant_id = p_tenant_id
    AND ts.deleted_at IS NULL;

  SELECT
    EXISTS (
      SELECT 1
        FROM organization_modules m
       WHERE m.tenant_id = p_tenant_id
         AND m.module_key = 'nie_poder'
         AND m.status IN ('active', 'trial')
         AND m.deleted_at IS NULL
    ),
    EXISTS (
      SELECT 1
        FROM organization_modules m
       WHERE m.tenant_id = p_tenant_id
         AND m.module_key = 'carpeta_inmueble'
         AND m.status IN ('active', 'trial')
         AND m.deleted_at IS NULL
    )
  INTO v_nie, v_carpeta;

  RETURN QUERY
  SELECT
    x.cliente_id,
    x.cliente_nombre,
    x.kind,
    x.expires_on,
    x.tone,
    x.bloque_id,
    x.expediente_id,
    x.documento_id,
    x.has_email,
    x.has_tel,
    x.last_requested_at
  FROM (
    SELECT
      c.id AS cliente_id,
      coalesce(
        nullif(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''),
        c.razon_social,
        c.nombre
      ) AS cliente_nombre,
      d.kind,
      d.expires_on,
      CASE
        WHEN d.expires_on < v_today THEN 'expired'
        ELSE 'expiring'
      END AS tone,
      d.bloque_id,
      d.expediente_id,
      d.documento_id,
      (nullif(btrim(c.email), '') IS NOT NULL) AS has_email,
      (nullif(btrim(c.tel), '') IS NOT NULL) AS has_tel,
      d.last_requested_at
    FROM (
      SELECT *
      FROM (
        SELECT DISTINCT ON (doc.cliente_id, doc.tipo)
          doc.cliente_id,
          doc.tipo AS kind,
          public.parse_office_date(doc.extracted->>'fields.expiry') AS expires_on,
          NULL::UUID AS bloque_id,
          NULL::UUID AS expediente_id,
          doc.id AS documento_id,
          NULL::TIMESTAMPTZ AS last_requested_at
        FROM documentos doc
        WHERE doc.tenant_id = p_tenant_id
          AND doc.deleted_at IS NULL
          AND doc.tipo IN ('dni_nie', 'pasaporte')
          AND doc.cliente_id IS NOT NULL
          AND public.parse_office_date(doc.extracted->>'fields.expiry') IS NOT NULL
        ORDER BY doc.cliente_id, doc.tipo, doc.created_at DESC
      ) id_docs
      UNION ALL
      SELECT
        e.cliente_id,
        b.template_key,
        coalesce(
          public.parse_office_date(b.fields->>'fields.expiry'),
          public.parse_office_date(b.fields->>'fecha_caducidad'),
          public.parse_office_date(b.fields->>'fecha_vencimiento')
        ),
        b.id,
        e.id,
        NULL::UUID,
        b.last_requested_at
      FROM bloques b
      JOIN expedientes e
        ON e.id = b.expediente_id
       AND e.deleted_at IS NULL
      WHERE b.tenant_id = p_tenant_id
        AND b.deleted_at IS NULL
        AND b.status IS DISTINCT FROM 'off'
        AND b.template_key IN ('poder', 'seguro')
    ) d
    JOIN clientes c
      ON c.id = d.cliente_id
     AND c.deleted_at IS NULL
    WHERE d.expires_on IS NOT NULL
      AND (
        (d.kind IN ('dni_nie', 'pasaporte'))
        OR (d.kind = 'poder' AND v_nie)
        OR (d.kind = 'seguro' AND v_carpeta)
      )
      AND (
        d.expires_on < v_today
        OR (
          CASE
            WHEN d.kind = 'seguro' THEN v_seguro
            ELSE v_poder
          END > 0
          AND d.expires_on <= v_today + (
            CASE
              WHEN d.kind = 'seguro' THEN v_seguro
              ELSE v_poder
            END
          )
        )
      )
  ) x
  ORDER BY
    CASE x.tone WHEN 'expired' THEN 0 ELSE 1 END,
    x.expires_on ASC,
    x.cliente_nombre;
END;
$$;

CREATE OR REPLACE FUNCTION public.expiring_items_count(p_tenant_id UUID)
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
    FROM public.expiring_items(p_tenant_id);
  RETURN COALESCE(v_n, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.expiring_items(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.expiring_items_count(UUID) TO authenticated;

COMMENT ON FUNCTION public.expiring_items(UUID) IS
  'DNI / pas / poder / seguro v okně warn_days. AI neodesílá.';
