-- Čerstvá koupě bez 210 a díry dodávek jsou u kupujícího.
-- Prodávající má plusvalía; 210 tipo 28 se navrhne na spisu, ne tady.

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
             AND coalesce(side.is_comprador, true)
          UNION ALL
          SELECT 'modelo_210'::TEXT
           WHERE coalesce(side.is_comprador, true)
             AND i.escritura_fecha >= (timezone('Europe/Madrid', now()))::date - 90
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
    LEFT JOIN LATERAL (
      SELECT bool_or(it.lado = 'comprador') AS is_comprador
        FROM inmueble_titulares it
       WHERE it.inmueble_id = i.id
         AND it.deleted_at IS NULL
         AND it.cliente_id = c.id
    ) side ON TRUE
    WHERE i.tenant_id = p_tenant_id
      AND i.deleted_at IS NULL
      AND i.escritura_fecha IS NOT NULL
  ) x
  WHERE cardinality(x.tasks) > 0
  ORDER BY x.escritura_fecha DESC, x.cliente_nombre;
END;
$$;

COMMENT ON FUNCTION public.after_notary(UUID) IS
  'Koupě s escritura_fecha: plusvalía; dodávka a čerstvé 210 jen u kupujícího. AI neodesílá.';
