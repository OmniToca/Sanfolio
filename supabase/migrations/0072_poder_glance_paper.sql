-- Čip poderu: datum z desky + papír, který kancelář otevře kliknutím.
-- AI nesahá.

DROP FUNCTION IF EXISTS public.cliente_poder_glance(UUID, UUID[]);

CREATE FUNCTION public.cliente_poder_glance(
  p_tenant_id UUID,
  p_cliente_ids UUID[]
)
RETURNS TABLE (
  cliente_id UUID,
  has_copy BOOLEAN,
  expiry_raw TEXT,
  documento_id UUID,
  storage_path TEXT,
  original_name TEXT
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    c.id AS cliente_id,
    EXISTS (
      SELECT 1
        FROM public.documentos d
       WHERE d.tenant_id = p_tenant_id
         AND d.cliente_id = c.id
         AND d.deleted_at IS NULL
         AND (
           d.tipo = 'copia_poder'
           OR EXISTS (
             SELECT 1
               FROM public.documento_bloques db
               JOIN public.bloques b
                 ON b.id = db.bloque_id
                AND b.deleted_at IS NULL
              WHERE db.documento_id = d.id
                AND db.deleted_at IS NULL
                AND b.template_key = 'poder'
           )
         )
    ) AS has_copy,
    coalesce(desk.expiry_raw, paper.expiry_raw) AS expiry_raw,
    paper.id AS documento_id,
    paper.storage_path,
    paper.original_name
  FROM public.clientes c
  LEFT JOIN LATERAL (
    SELECT
      b.id AS bloque_id,
      coalesce(
        nullif(btrim(b.fields->>'fields.fecha_caducidad'), ''),
        nullif(btrim(b.fields->>'fields.expiry'), ''),
        nullif(btrim(b.fields->>'fecha_caducidad'), '')
      ) AS expiry_raw
      FROM public.bloques b
      JOIN public.expedientes e
        ON e.id = b.expediente_id
       AND e.deleted_at IS NULL
     WHERE e.cliente_id = c.id
       AND e.tenant_id = p_tenant_id
       AND b.template_key = 'poder'
       AND b.deleted_at IS NULL
     ORDER BY public.parse_office_date(
       coalesce(
         b.fields->>'fields.fecha_caducidad',
         b.fields->>'fields.expiry',
         b.fields->>'fecha_caducidad'
       )
     ) ASC NULLS LAST
     LIMIT 1
  ) desk ON true
  LEFT JOIN LATERAL (
    SELECT
      d.id,
      d.storage_path,
      d.original_name,
      coalesce(
        nullif(btrim(d.extracted->>'fields.fecha_caducidad'), ''),
        nullif(btrim(d.extracted->>'fields.expiry'), ''),
        nullif(btrim(d.extracted->>'fecha_caducidad'), '')
      ) AS expiry_raw
      FROM public.documentos d
     WHERE d.tenant_id = p_tenant_id
       AND d.cliente_id = c.id
       AND d.deleted_at IS NULL
       AND d.storage_purged_at IS NULL
       AND (
         d.tipo = 'copia_poder'
         OR EXISTS (
           SELECT 1
             FROM public.documento_bloques db
             JOIN public.bloques b
               ON b.id = db.bloque_id
              AND b.deleted_at IS NULL
            WHERE db.documento_id = d.id
              AND db.deleted_at IS NULL
              AND b.template_key = 'poder'
         )
       )
     ORDER BY
       CASE
         WHEN desk.bloque_id IS NOT NULL AND EXISTS (
           SELECT 1
             FROM public.documento_bloques db
            WHERE db.documento_id = d.id
              AND db.bloque_id = desk.bloque_id
              AND db.deleted_at IS NULL
         ) THEN 0
         WHEN d.tipo = 'copia_poder' THEN 1
         ELSE 2
       END,
       d.created_at DESC
     LIMIT 1
  ) paper ON true
 WHERE c.tenant_id = p_tenant_id
   AND c.id = ANY (coalesce(p_cliente_ids, ARRAY[]::UUID[]))
   AND public.can_access_tenant(p_tenant_id);
$$;

GRANT EXECUTE ON FUNCTION public.cliente_poder_glance(UUID, UUID[]) TO authenticated;

COMMENT ON FUNCTION public.cliente_poder_glance(UUID, UUID[]) IS
  'Kopie poderu + datum z desky + papír k otevření. AI neukládá.';
