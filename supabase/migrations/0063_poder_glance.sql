-- Přehled klientů: máme kopii poderu? Datum z desky, ne z OCR odpadu.
-- AI neukládá.

CREATE OR REPLACE FUNCTION public.cliente_poder_glance(
  p_tenant_id UUID,
  p_cliente_ids UUID[]
)
RETURNS TABLE (
  cliente_id UUID,
  has_copy BOOLEAN,
  expiry_raw TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
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
    (
      SELECT coalesce(
               nullif(btrim(b.fields->>'fields.fecha_caducidad'), ''),
               nullif(btrim(b.fields->>'fields.expiry'), ''),
               nullif(btrim(b.fields->>'fecha_caducidad'), '')
             )
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
    ) AS expiry_raw
  FROM public.clientes c
 WHERE c.tenant_id = p_tenant_id
   AND c.id = ANY (coalesce(p_cliente_ids, ARRAY[]::UUID[]))
   AND public.can_access_tenant(p_tenant_id);
$$;

GRANT EXECUTE ON FUNCTION public.cliente_poder_glance(UUID, UUID[]) TO authenticated;

COMMENT ON FUNCTION public.cliente_poder_glance(UUID, UUID[]) IS
  'Kopie poderu + datum z desky. Pro seznam a kartu, ne druhá evidence.';
