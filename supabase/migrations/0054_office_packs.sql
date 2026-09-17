-- Sezóna 210 a balíček po notáři. Čtení desky, žádný save/send.

CREATE OR REPLACE FUNCTION public.season_210(p_tenant_id UUID)
RETURNS TABLE (
  cliente_id UUID,
  cliente_nombre TEXT,
  expediente_id UUID,
  bloque_id UUID,
  periodo TEXT,
  periodicity TEXT,
  due_on DATE,
  bloque_status TEXT,
  missing_docs TEXT[]
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
    c.id,
    coalesce(
      nullif(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''),
      c.razon_social,
      c.nombre
    ) AS cliente_nombre,
    e.id,
    b.id,
    nullif(btrim(coalesce(b.fields->>'fields.modeloPeriod', '')), ''),
    nullif(btrim(coalesce(b.fields->>'fields.periodicity', '')), ''),
    coalesce(
      p.due_on,
      public.try_parse_date(b.fields->>'fields.deadline')
    ),
    b.status::TEXT,
    (
      SELECT coalesce(array_agg(req.tipo ORDER BY req.tipo), '{}')
      FROM unnest(coalesce(t.required_doc_types, '{}'::TEXT[])) AS req(tipo)
      WHERE NOT EXISTS (
        SELECT 1
          FROM documentos d
         WHERE d.bloque_id = b.id
           AND d.deleted_at IS NULL
           AND d.tipo = req.tipo
      )
    ) AS missing_docs
  FROM bloques b
  JOIN expedientes e
    ON e.id = b.expediente_id
   AND e.deleted_at IS NULL
  JOIN clientes c
    ON c.id = e.cliente_id
   AND c.deleted_at IS NULL
  LEFT JOIN bloque_templates t
    ON t.key = b.template_key
  LEFT JOIN LATERAL (
    SELECT pz.due_on
      FROM plazos pz
     WHERE pz.bloque_id = b.id
       AND pz.kind = 'modelo_210'
       AND pz.deleted_at IS NULL
       AND pz.completed_at IS NULL
     ORDER BY pz.due_on
     LIMIT 1
  ) p ON TRUE
  WHERE b.tenant_id = p_tenant_id
    AND b.deleted_at IS NULL
    AND b.template_key = 'modelo_210'
    AND b.status NOT IN ('off', 'done')
    AND e.tipo = 'impuestos_210'
    AND e.estado NOT IN ('hecho', 'archivado')
    AND btrim(coalesce(b.fields->>'fields.filed', '')) = ''
  ORDER BY
    (p.due_on IS NULL) ASC,
    p.due_on ASC NULLS LAST,
    c.nombre;
END;
$$;

CREATE OR REPLACE FUNCTION public.season_210_count(p_tenant_id UUID)
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
    FROM public.season_210(p_tenant_id);
  RETURN COALESCE(v_n, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.after_notary(p_tenant_id UUID)
RETURNS TABLE (
  cliente_id UUID,
  cliente_nombre TEXT,
  inmueble_id UUID,
  expediente_id UUID,
  direccion TEXT,
  escritura_fecha DATE,
  tax_expediente_id UUID,
  tasks TEXT[]
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
    x.inmueble_id,
    x.expediente_id,
    x.direccion,
    x.escritura_fecha,
    x.tax_expediente_id,
    x.tasks
  FROM (
    SELECT
      c.id AS cliente_id,
      coalesce(
        nullif(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''),
        c.razon_social,
        c.nombre
      ) AS cliente_nombre,
      i.id AS inmueble_id,
      e.id AS expediente_id,
      i.direccion,
      i.escritura_fecha,
      tax.id AS tax_expediente_id,
      (
        SELECT coalesce(array_agg(k ORDER BY k), '{}')
        FROM (
          SELECT 'plusvalia'::TEXT AS k
           WHERE EXISTS (
             SELECT 1 FROM bloques b
              WHERE b.expediente_id = e.id
                AND b.deleted_at IS NULL
                AND b.template_key = 'plusvalia'
                AND b.status NOT IN ('off', 'done')
           )
          UNION ALL
          SELECT b.template_key
            FROM bloques b
           WHERE b.expediente_id = e.id
             AND b.deleted_at IS NULL
             AND b.template_key IN ('agua', 'luz', 'gaz', 'comunidad')
             AND b.status IN ('missing_data', 'missing_document')
          UNION ALL
          SELECT 'modelo_210'::TEXT
           WHERE i.escritura_fecha >= (timezone('Europe/Madrid', now()))::date - 90
             AND (
               tax.id IS NULL
               OR btrim(coalesce(tax.fields->>'fields.filed', '')) = ''
             )
             AND coalesce(tax.status::text, 'off') IS DISTINCT FROM 'done'
        ) t(k)
      ) AS tasks
    FROM inmuebles i
    JOIN clientes c
      ON c.id = i.cliente_id
     AND c.deleted_at IS NULL
    JOIN LATERAL (
      SELECT exp.id
        FROM expedientes exp
       WHERE exp.inmueble_id = i.id
         AND exp.tipo = 'compraventa'
         AND exp.deleted_at IS NULL
       ORDER BY exp.created_at DESC
       LIMIT 1
    ) e ON TRUE
    LEFT JOIN LATERAL (
      SELECT exp.id, b.fields, b.status
        FROM expedientes exp
        JOIN bloques b
          ON b.expediente_id = exp.id
         AND b.template_key = 'modelo_210'
         AND b.deleted_at IS NULL
       WHERE exp.inmueble_id = i.id
         AND exp.tipo = 'impuestos_210'
         AND exp.deleted_at IS NULL
         AND exp.estado IS DISTINCT FROM 'archivado'
       ORDER BY exp.created_at DESC
       LIMIT 1
    ) tax ON TRUE
    WHERE i.tenant_id = p_tenant_id
      AND i.deleted_at IS NULL
      AND i.escritura_fecha IS NOT NULL
  ) x
  WHERE cardinality(x.tasks) > 0
  ORDER BY x.escritura_fecha DESC, x.cliente_nombre;
END;
$$;

CREATE OR REPLACE FUNCTION public.after_notary_count(p_tenant_id UUID)
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
    FROM public.after_notary(p_tenant_id);
  RETURN COALESCE(v_n, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.season_210(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.season_210_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.after_notary(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.after_notary_count(UUID) TO authenticated;

COMMENT ON FUNCTION public.season_210(UUID) IS
  'Otevřené modelo 210 bez podání. AI neodesílá ani nepodává AEAT.';
COMMENT ON FUNCTION public.after_notary(UUID) IS
  'Koupě s escritura_fecha, kde zbývá plusvalía / dodávka / čerstvé 210. AI neodesílá.';
