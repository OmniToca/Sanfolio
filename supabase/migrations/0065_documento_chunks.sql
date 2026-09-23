-- Sémantické hledání v přepisu. FTS zůstává. AI jen čte kousky.

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;

CREATE TABLE IF NOT EXISTS public.documento_chunks (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID NOT NULL REFERENCES public.tenants (id),
  documento_id  UUID NOT NULL REFERENCES public.documentos (id),
  cliente_id    UUID NOT NULL REFERENCES public.clientes (id),
  chunk_index   INT NOT NULL,
  content       TEXT NOT NULL,
  embedding     extensions.vector(1536) NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at    TIMESTAMPTZ
);

COMMENT ON TABLE public.documento_chunks IS
  'Kousky body_text + embedding. tenant_id povinný. Žádný globální katalog norem.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_documento_chunks_live
  ON public.documento_chunks (documento_id, chunk_index)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_documento_chunks_tenant
  ON public.documento_chunks (tenant_id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_documento_chunks_embedding
  ON public.documento_chunks
  USING hnsw (embedding extensions.vector_cosine_ops)
  WHERE deleted_at IS NULL;

ALTER TABLE public.documento_chunks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS documento_chunks_select ON public.documento_chunks;
CREATE POLICY documento_chunks_select ON public.documento_chunks
  FOR SELECT TO authenticated
  USING (public.can_access_tenant(tenant_id));

DROP POLICY IF EXISTS documento_chunks_insert ON public.documento_chunks;
CREATE POLICY documento_chunks_insert ON public.documento_chunks
  FOR INSERT TO authenticated
  WITH CHECK (public.can_access_tenant(tenant_id));

DROP POLICY IF EXISTS documento_chunks_update ON public.documento_chunks;
CREATE POLICY documento_chunks_update ON public.documento_chunks
  FOR UPDATE TO authenticated
  USING (public.can_access_tenant(tenant_id))
  WITH CHECK (public.can_access_tenant(tenant_id));

DROP TRIGGER IF EXISTS trg_documento_chunks_updated ON public.documento_chunks;
CREATE TRIGGER trg_documento_chunks_updated
  BEFORE UPDATE ON public.documento_chunks
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_documento_chunks_no_hard_delete ON public.documento_chunks;
CREATE TRIGGER trg_documento_chunks_no_hard_delete
  BEFORE DELETE ON public.documento_chunks
  FOR EACH ROW EXECUTE FUNCTION public.forbid_hard_delete();

CREATE OR REPLACE FUNCTION public.trg_documento_chunks_on_doc_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
    UPDATE public.documento_chunks
       SET deleted_at = NEW.deleted_at
     WHERE documento_id = NEW.id
       AND deleted_at IS NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_documento_chunks_on_doc_delete ON public.documentos;
CREATE TRIGGER trg_documento_chunks_on_doc_delete
  AFTER UPDATE OF deleted_at ON public.documentos
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_documento_chunks_on_doc_delete();

-- Atomic replace z extract / backfill. Embedding pole je JSON pole čísel.
CREATE OR REPLACE FUNCTION public.replace_documento_chunks(
  p_documento_id UUID,
  p_chunks JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  d RECORD;
  c JSONB;
  v_i INT := 0;
  v_emb FLOAT[];
BEGIN
  SELECT id, tenant_id, cliente_id, deleted_at
    INTO d
    FROM public.documentos
   WHERE id = p_documento_id;
  IF d.id IS NULL THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF d.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT (
    public.can_access_tenant(d.tenant_id)
    OR auth.role() = 'service_role'
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_chunks IS NULL OR jsonb_typeof(p_chunks) <> 'array' THEN
    RAISE EXCEPTION 'bad_chunks';
  END IF;
  IF jsonb_array_length(p_chunks) > 80 THEN
    RAISE EXCEPTION 'too_many_chunks';
  END IF;

  UPDATE public.documento_chunks
     SET deleted_at = now()
   WHERE documento_id = p_documento_id
     AND deleted_at IS NULL;

  FOR c IN SELECT value FROM jsonb_array_elements(p_chunks)
  LOOP
    v_i := v_i + 1;
    SELECT array_agg(x::float ORDER BY ord)
      INTO v_emb
      FROM jsonb_array_elements_text(c->'embedding') WITH ORDINALITY AS t(x, ord);
    IF v_emb IS NULL OR array_length(v_emb, 1) IS DISTINCT FROM 1536 THEN
      RAISE EXCEPTION 'bad_embedding';
    END IF;
    INSERT INTO public.documento_chunks (
      tenant_id, documento_id, cliente_id, chunk_index, content, embedding
    ) VALUES (
      d.tenant_id,
      p_documento_id,
      d.cliente_id,
      coalesce((c->>'chunk_index')::int, v_i - 1),
      left(btrim(coalesce(c->>'content', '')), 4000),
      v_emb::extensions.vector(1536)
    );
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.replace_documento_chunks(UUID, JSONB) TO authenticated, service_role;

COMMENT ON FUNCTION public.replace_documento_chunks(UUID, JSONB) IS
  'Přepíše kousky přepisu. AI sem nesmí z desky; jen extract/backfill.';

CREATE OR REPLACE FUNCTION public.search_document_chunks(
  p_tenant_id UUID,
  p_query_embedding JSONB,
  p_limit INT DEFAULT 12
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_limit INT := least(greatest(coalesce(p_limit, 12), 1), 12);
  v_arr FLOAT[];
  v_emb extensions.vector(1536);
  v_total BIGINT;
  v_items JSONB;
  v_has_text BOOLEAN;
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  SELECT array_agg(x::float ORDER BY ord)
    INTO v_arr
    FROM jsonb_array_elements_text(p_query_embedding) WITH ORDINALITY AS t(x, ord);
  IF v_arr IS NULL OR array_length(v_arr, 1) IS DISTINCT FROM 1536 THEN
    RAISE EXCEPTION 'bad_embedding';
  END IF;
  v_emb := v_arr::extensions.vector(1536);

  SELECT exists(
    SELECT 1
      FROM documentos d
     WHERE d.tenant_id = p_tenant_id
       AND d.deleted_at IS NULL
       AND d.body_text IS NOT NULL
       AND length(btrim(d.body_text)) > 0
  ) INTO v_has_text;

  SELECT coalesce(jsonb_agg(x.obj ORDER BY x.dist), '[]'::jsonb)
    INTO v_items
    FROM (
      SELECT jsonb_build_object(
        'cliente_id', best.cliente_id,
        'nombre', best.nombre,
        'document_id', best.documento_id,
        'original_name', best.original_name,
        'tipo', best.tipo,
        'bloque_key', (
          SELECT b2.template_key
            FROM public.documento_bloques db
            JOIN public.bloques b2
              ON b2.id = db.bloque_id AND b2.deleted_at IS NULL
           WHERE db.documento_id = best.documento_id AND db.deleted_at IS NULL
           ORDER BY db.created_at
           LIMIT 1
        ),
        'albums', coalesce((
          SELECT jsonb_agg(b2.template_key ORDER BY db.created_at)
            FROM public.documento_bloques db
            JOIN public.bloques b2
              ON b2.id = db.bloque_id AND b2.deleted_at IS NULL
           WHERE db.documento_id = best.documento_id AND db.deleted_at IS NULL
        ), '[]'::jsonb),
        'inmueble_id', best.inmueble_id,
        'direccion', best.direccion,
        'storage_path', best.storage_path,
        'snippet', left(best.content, 280),
        'via', 'vector'
      ) AS obj,
      best.dist
      FROM (
        SELECT DISTINCT ON (ch.documento_id)
          c.id AS cliente_id,
          trim(both from concat_ws(' ', c.nombre, c.apellidos)) AS nombre,
          d.id AS documento_id,
          d.original_name,
          d.tipo,
          d.inmueble_id,
          i.direccion,
          d.storage_path,
          ch.content,
          (ch.embedding <=> v_emb) AS dist
        FROM public.documento_chunks ch
        JOIN public.documentos d
          ON d.id = ch.documento_id AND d.deleted_at IS NULL
        JOIN public.clientes c
          ON c.id = d.cliente_id AND c.deleted_at IS NULL
        LEFT JOIN public.inmuebles i
          ON i.id = d.inmueble_id AND i.deleted_at IS NULL
        WHERE ch.tenant_id = p_tenant_id
          AND ch.deleted_at IS NULL
        ORDER BY ch.documento_id, ch.embedding <=> v_emb
      ) best
      ORDER BY best.dist
      LIMIT v_limit
    ) x;

  v_total := coalesce(jsonb_array_length(v_items), 0);

  INSERT INTO audit_logs (
    tenant_id, actor_id, impersonation_session_id,
    action, entity_table, after
  ) VALUES (
    p_tenant_id,
    auth.uid(),
    (SELECT s.id FROM support_view_sessions s
      WHERE s.support_user_id = auth.uid()
        AND s.ended_at IS NULL
      ORDER BY s.started_at DESC LIMIT 1),
    'ai.tool',
    'documento_chunks',
    jsonb_build_object('tool', 'search_document_chunks', 'total', v_total)
  );

  RETURN jsonb_build_object(
    'total', v_total,
    'filled_on_desk', v_has_text,
    'items', coalesce(v_items, '[]'::jsonb)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_document_chunks(UUID, JSONB, INT) TO authenticated;

COMMENT ON FUNCTION public.search_document_chunks(UUID, JSONB, INT) IS
  'Read-only cosine kousků. Lidská otázka, ne jen přesné slovo. Žádný save.';
