-- Stoh: /prepis jen extract, který už má blok. Sklad bez bloku žije na /stoh.

CREATE OR REPLACE FUNCTION public.pending_extract_queue(p_tenant_id UUID)
RETURNS TABLE (
  draft_id UUID,
  cliente_id UUID,
  cliente_nombre TEXT,
  bloque_key TEXT,
  storage_path TEXT,
  documento_id UUID,
  doc_tipo TEXT,
  original_name TEXT,
  expediente_id UUID,
  fields JSONB,
  created_at TIMESTAMPTZ
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
    d.id,
    d.cliente_id,
    COALESCE(c.nombre, ''),
    COALESCE(d.bloque_key, 'cliente_snapshot'),
    d.storage_path,
    doc.id,
    doc.tipo,
    doc.original_name,
    b.expediente_id,
    d.fields,
    d.created_at
  FROM public.ai_drafts d
  LEFT JOIN public.clientes c
    ON c.id = d.cliente_id AND c.deleted_at IS NULL
  LEFT JOIN LATERAL (
    SELECT x.id, x.tipo, x.original_name, x.bloque_id, x.extracted
      FROM public.documentos x
     WHERE x.deleted_at IS NULL
       AND x.tenant_id = d.tenant_id
       AND (
         (d.documento_id IS NOT NULL AND x.id = d.documento_id)
         OR (d.documento_id IS NULL AND d.storage_path IS NOT NULL
             AND x.storage_path = d.storage_path)
       )
     ORDER BY CASE WHEN x.id = d.documento_id THEN 0 ELSE 1 END
     LIMIT 1
  ) doc ON true
  LEFT JOIN public.bloques b
    ON b.id = doc.bloque_id AND b.deleted_at IS NULL
  WHERE d.tenant_id = p_tenant_id
    AND d.deleted_at IS NULL
    AND d.purpose = 'extract_document'
    AND (d.expires_at IS NULL OR d.expires_at > now())
    AND d.cliente_id IS NOT NULL
    AND (doc.id IS NULL OR doc.bloque_id IS NOT NULL)
    AND (
      doc.id IS NULL
      OR doc.extracted IS NULL
      OR doc.extracted = '{}'::jsonb
    )
  ORDER BY d.created_at DESC;
END;
$$;

COMMENT ON FUNCTION public.pending_extract_queue(UUID) IS
  'Extract s blokem, bez Guardar. Stoh (bloque_id null) je /stoh, ne /prepis.';
