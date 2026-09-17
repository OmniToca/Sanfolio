-- Fronta přepisů: extract u dokumentu neexpiruje, dokud gestor Guardar / Zahodit.
-- TTL 24 h zůstává u ostatních účelů (extract_text, chat). AI dál neukládá desku.

ALTER TABLE public.ai_drafts
  ADD COLUMN IF NOT EXISTS documento_id UUID REFERENCES public.documentos (id);

ALTER TABLE public.ai_drafts
  ALTER COLUMN expires_at DROP NOT NULL;

COMMENT ON COLUMN public.ai_drafts.expires_at IS
  'NULL = čeká na Guardar/Zahodit (extract u souboru). Jinak TTL 24 h.';

COMMENT ON COLUMN public.ai_drafts.documento_id IS
  'Doklad, ze kterého návrh vznikl. Fronta /prepis sem sahá, ne na desku přímo.';

UPDATE public.ai_drafts d
   SET documento_id = doc.id
  FROM public.documentos doc
 WHERE d.documento_id IS NULL
   AND d.storage_path IS NOT NULL
   AND d.storage_path = doc.storage_path
   AND d.tenant_id = doc.tenant_id
   AND d.deleted_at IS NULL
   AND doc.deleted_at IS NULL;

UPDATE public.ai_drafts
   SET expires_at = NULL
 WHERE purpose = 'extract_document'
   AND deleted_at IS NULL
   AND (storage_path IS NOT NULL OR documento_id IS NOT NULL);

CREATE INDEX IF NOT EXISTS idx_ai_drafts_extract_queue
  ON public.ai_drafts (tenant_id, created_at DESC)
  WHERE deleted_at IS NULL AND purpose = 'extract_document';

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
    AND (
      doc.id IS NULL
      OR doc.extracted IS NULL
      OR doc.extracted = '{}'::jsonb
    )
  ORDER BY d.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.pending_extract_count(p_tenant_id UUID)
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
    FROM public.pending_extract_queue(p_tenant_id);
  RETURN COALESCE(v_n, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.pending_extract_queue(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pending_extract_count(UUID) TO authenticated;

COMMENT ON FUNCTION public.pending_extract_queue(UUID) IS
  'Návrhy extract_document bez Guardar. AI sem neukládá extracted.';
