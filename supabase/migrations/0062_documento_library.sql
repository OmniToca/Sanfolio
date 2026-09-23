-- Knihovna papírů: jeden řádek u klienta, alba přes documento_bloques,
-- finca na documentos.inmueble_id, hash na duplicitu bajtů.
-- documentos.bloque_id zůstává denormalizovaný (první živé album).

ALTER TABLE public.documentos
  ADD COLUMN IF NOT EXISTS inmueble_id UUID REFERENCES public.inmuebles (id),
  ADD COLUMN IF NOT EXISTS content_sha256 TEXT;

COMMENT ON COLUMN public.documentos.inmueble_id IS
  'Finca papíru. NULL = papír klienta (DNI, mail). Jedna finca na řádek.';
COMMENT ON COLUMN public.documentos.content_sha256 IS
  'SHA-256 hex bajtů. Stejný hash u živého klienta = duplicita souboru.';

CREATE INDEX IF NOT EXISTS idx_documentos_cliente_sha
  ON public.documentos (cliente_id, content_sha256)
  WHERE deleted_at IS NULL AND content_sha256 IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_documentos_cliente_inmueble
  ON public.documentos (cliente_id, inmueble_id)
  WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS public.documento_bloques (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID NOT NULL REFERENCES public.tenants (id),
  documento_id  UUID NOT NULL REFERENCES public.documentos (id),
  bloque_id     UUID NOT NULL REFERENCES public.bloques (id),
  tipo          TEXT NOT NULL DEFAULT 'other',
  source        TEXT NOT NULL CHECK (source IN ('human', 'ai')),
  created_by    UUID REFERENCES public.profiles (id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at    TIMESTAMPTZ
);

COMMENT ON TABLE public.documento_bloques IS
  'Alba desky. Stejný papír smí viset ve víc blocích jedné finca. Nula = hromada.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_documento_bloques_live
  ON public.documento_bloques (documento_id, bloque_id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_documento_bloques_bloque
  ON public.documento_bloques (bloque_id)
  WHERE deleted_at IS NULL;

ALTER TABLE public.documento_bloques ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS documento_bloques_select ON public.documento_bloques;
CREATE POLICY documento_bloques_select ON public.documento_bloques
  FOR SELECT TO authenticated
  USING (public.can_access_tenant(tenant_id));

DROP POLICY IF EXISTS documento_bloques_insert ON public.documento_bloques;
CREATE POLICY documento_bloques_insert ON public.documento_bloques
  FOR INSERT TO authenticated
  WITH CHECK (public.can_access_tenant(tenant_id));

DROP POLICY IF EXISTS documento_bloques_update ON public.documento_bloques;
CREATE POLICY documento_bloques_update ON public.documento_bloques
  FOR UPDATE TO authenticated
  USING (public.can_access_tenant(tenant_id))
  WITH CHECK (public.can_access_tenant(tenant_id));

-- Inmueble musí být stejného klienta. Album jen bloky té finca, když je finca známá.
CREATE OR REPLACE FUNCTION public.documento_library_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_doc public.documentos%ROWTYPE;
  v_inm_cliente UUID;
  v_bloque_tenant UUID;
  v_exp_cliente UUID;
  v_exp_inm UUID;
BEGIN
  IF TG_TABLE_NAME = 'documentos' THEN
    IF NEW.inmueble_id IS NOT NULL THEN
      SELECT cliente_id INTO v_inm_cliente
        FROM public.inmuebles
       WHERE id = NEW.inmueble_id AND deleted_at IS NULL;
      IF v_inm_cliente IS NULL OR v_inm_cliente IS DISTINCT FROM NEW.cliente_id THEN
        RAISE EXCEPTION 'wrong_inmueble';
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  SELECT * INTO v_doc FROM public.documentos WHERE id = NEW.documento_id;
  IF v_doc.id IS NULL OR v_doc.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF v_doc.tenant_id IS DISTINCT FROM NEW.tenant_id THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT b.tenant_id, e.cliente_id, e.inmueble_id
    INTO v_bloque_tenant, v_exp_cliente, v_exp_inm
    FROM public.bloques b
    JOIN public.expedientes e ON e.id = b.expediente_id
   WHERE b.id = NEW.bloque_id
     AND b.deleted_at IS NULL
     AND e.deleted_at IS NULL;
  IF v_bloque_tenant IS NULL THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF v_bloque_tenant IS DISTINCT FROM NEW.tenant_id THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF v_exp_cliente IS DISTINCT FROM v_doc.cliente_id THEN
    RAISE EXCEPTION 'wrong_cliente';
  END IF;
  IF NEW.deleted_at IS NULL
     AND v_doc.inmueble_id IS NOT NULL
     AND v_exp_inm IS NOT NULL
     AND v_exp_inm IS DISTINCT FROM v_doc.inmueble_id THEN
    RAISE EXCEPTION 'wrong_inmueble';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_documentos_library ON public.documentos;
CREATE TRIGGER trg_documentos_library
  BEFORE INSERT OR UPDATE OF inmueble_id, cliente_id
  ON public.documentos
  FOR EACH ROW
  EXECUTE FUNCTION public.documento_library_guard();

DROP TRIGGER IF EXISTS trg_documento_bloques_library ON public.documento_bloques;
CREATE TRIGGER trg_documento_bloques_library
  BEFORE INSERT OR UPDATE
  ON public.documento_bloques
  FOR EACH ROW
  EXECUTE FUNCTION public.documento_library_guard();

CREATE OR REPLACE FUNCTION public.sync_documento_primary_bloque(p_documento_id UUID)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_bloque UUID;
BEGIN
  SELECT db.bloque_id INTO v_bloque
    FROM public.documento_bloques db
   WHERE db.documento_id = p_documento_id
     AND db.deleted_at IS NULL
   ORDER BY db.created_at ASC
   LIMIT 1;
  UPDATE public.documentos
     SET bloque_id = v_bloque,
         updated_at = now()
   WHERE id = p_documento_id
     AND deleted_at IS NULL
     AND bloque_id IS DISTINCT FROM v_bloque;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_documento_inmueble(
  p_documento_id UUID,
  p_inmueble_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doc public.documentos%ROWTYPE;
BEGIN
  SELECT * INTO v_doc FROM public.documentos
   WHERE id = p_documento_id AND deleted_at IS NULL;
  IF v_doc.id IS NULL THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_doc.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.documentos
     SET inmueble_id = p_inmueble_id,
         updated_at = now()
   WHERE id = p_documento_id;

  IF p_inmueble_id IS NOT NULL THEN
    UPDATE public.documento_bloques db
       SET deleted_at = now()
      FROM public.bloques b
      JOIN public.expedientes e ON e.id = b.expediente_id
     WHERE db.documento_id = p_documento_id
       AND db.deleted_at IS NULL
       AND db.bloque_id = b.id
       AND e.inmueble_id IS NOT NULL
       AND e.inmueble_id IS DISTINCT FROM p_inmueble_id;
  END IF;

  PERFORM public.sync_documento_primary_bloque(p_documento_id);

  INSERT INTO public.audit_logs (
    tenant_id, actor_id, action, entity_table, entity_id, after
  ) VALUES (
    v_doc.tenant_id,
    auth.uid(),
    'documento.set_inmueble',
    'documentos',
    p_documento_id,
    jsonb_build_object('inmueble_id', p_inmueble_id)
  );

  RETURN p_documento_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_documento_placement(
  p_documento_id UUID,
  p_bloque_id UUID,
  p_tipo TEXT,
  p_on BOOLEAN
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doc public.documentos%ROWTYPE;
  v_tenant UUID;
  v_exp_inm UUID;
  v_tipo TEXT := nullif(btrim(coalesce(p_tipo, '')), '');
BEGIN
  SELECT * INTO v_doc FROM public.documentos
   WHERE id = p_documento_id AND deleted_at IS NULL;
  IF v_doc.id IS NULL THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_doc.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  v_tenant := v_doc.tenant_id;
  IF v_tipo IS NULL THEN
    v_tipo := coalesce(nullif(btrim(v_doc.tipo), ''), 'other');
  END IF;

  SELECT e.inmueble_id INTO v_exp_inm
    FROM public.bloques b
    JOIN public.expedientes e ON e.id = b.expediente_id
   WHERE b.id = p_bloque_id AND b.deleted_at IS NULL AND e.deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;

  IF p_on
     AND v_doc.inmueble_id IS NULL
     AND v_exp_inm IS NOT NULL THEN
    UPDATE public.documentos
       SET inmueble_id = v_exp_inm, updated_at = now()
     WHERE id = p_documento_id;
    v_doc.inmueble_id := v_exp_inm;
  END IF;

  IF p_on THEN
    UPDATE public.documento_bloques
       SET tipo = v_tipo,
           source = 'human',
           created_by = auth.uid()
     WHERE documento_id = p_documento_id
       AND bloque_id = p_bloque_id
       AND deleted_at IS NULL;
    IF NOT FOUND THEN
      UPDATE public.documento_bloques db
         SET deleted_at = NULL,
             tipo = v_tipo,
             source = 'human',
             created_by = auth.uid()
        FROM (
          SELECT id
            FROM public.documento_bloques
           WHERE documento_id = p_documento_id
             AND bloque_id = p_bloque_id
             AND deleted_at IS NOT NULL
           ORDER BY created_at DESC
           LIMIT 1
        ) x
       WHERE db.id = x.id;
      IF NOT FOUND THEN
        INSERT INTO public.documento_bloques (
          tenant_id, documento_id, bloque_id, tipo, source, created_by
        )
        SELECT v_tenant, p_documento_id, p_bloque_id, v_tipo, 'human', auth.uid()
         WHERE NOT EXISTS (
           SELECT 1 FROM public.documento_bloques
            WHERE documento_id = p_documento_id
              AND bloque_id = p_bloque_id
              AND deleted_at IS NULL
         );
      END IF;
    END IF;
  ELSE
    UPDATE public.documento_bloques
       SET deleted_at = now()
     WHERE documento_id = p_documento_id
       AND bloque_id = p_bloque_id
       AND deleted_at IS NULL;
  END IF;

  PERFORM public.sync_documento_primary_bloque(p_documento_id);

  INSERT INTO public.audit_logs (
    tenant_id, actor_id, action, entity_table, entity_id, after
  ) VALUES (
    v_tenant,
    auth.uid(),
    CASE WHEN p_on THEN 'documento.place' ELSE 'documento.unplace' END,
    'documento_bloques',
    p_documento_id,
    jsonb_build_object('bloque_id', p_bloque_id, 'tipo', v_tipo, 'on', p_on)
  );

  RETURN p_documento_id;
END;
$$;

-- Extract na pozadí. Nepřepíše lidské album. Desku nepisuje.
CREATE OR REPLACE FUNCTION public.place_documento_ai(
  p_documento_id UUID,
  p_bloque_id UUID,
  p_tipo TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doc public.documentos%ROWTYPE;
  v_tipo TEXT := nullif(btrim(coalesce(p_tipo, '')), '');
  v_exp_inm UUID;
  v_human INT;
BEGIN
  SELECT * INTO v_doc FROM public.documentos
   WHERE id = p_documento_id AND deleted_at IS NULL;
  IF v_doc.id IS NULL THEN
    RETURN false;
  END IF;
  IF auth.uid() IS NOT NULL AND NOT public.can_access_tenant(v_doc.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF v_tipo IS NULL THEN
    v_tipo := coalesce(nullif(btrim(v_doc.tipo), ''), 'other');
  END IF;

  SELECT count(*) INTO v_human
    FROM public.documento_bloques
   WHERE documento_id = p_documento_id
     AND deleted_at IS NULL
     AND source = 'human';
  IF v_human > 0 THEN
    RETURN false;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.documento_bloques
     WHERE documento_id = p_documento_id AND deleted_at IS NULL
  ) THEN
    RETURN false;
  END IF;

  SELECT e.inmueble_id INTO v_exp_inm
    FROM public.bloques b
    JOIN public.expedientes e ON e.id = b.expediente_id
   WHERE b.id = p_bloque_id AND b.deleted_at IS NULL AND e.deleted_at IS NULL;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  IF v_doc.inmueble_id IS NOT NULL
     AND v_exp_inm IS NOT NULL
     AND v_doc.inmueble_id IS DISTINCT FROM v_exp_inm THEN
    RETURN false;
  END IF;
  IF v_doc.inmueble_id IS NULL AND v_exp_inm IS NOT NULL THEN
    UPDATE public.documentos
       SET inmueble_id = v_exp_inm, updated_at = now()
     WHERE id = p_documento_id;
  END IF;

  INSERT INTO public.documento_bloques (
    tenant_id, documento_id, bloque_id, tipo, source, created_by
  ) VALUES (
    v_doc.tenant_id, p_documento_id, p_bloque_id, v_tipo, 'ai', auth.uid()
  );

  PERFORM public.sync_documento_primary_bloque(p_documento_id);

  INSERT INTO public.audit_logs (
    tenant_id, actor_id, action, entity_table, entity_id, after
  ) VALUES (
    v_doc.tenant_id,
    auth.uid(),
    'documento.place',
    'documento_bloques',
    p_documento_id,
    jsonb_build_object('bloque_id', p_bloque_id, 'tipo', v_tipo, 'source', 'ai')
  );
  RETURN true;
EXCEPTION
  WHEN unique_violation THEN
    RETURN false;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_documento_inmueble(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_documento_placement(UUID, UUID, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.place_documento_ai(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_documento_primary_bloque(UUID) TO authenticated;

COMMENT ON FUNCTION public.set_documento_inmueble(UUID, UUID) IS
  'Člověk nastaví finca. Alba cizího bytu se sundají. AI nevolá.';
COMMENT ON FUNCTION public.set_documento_placement(UUID, UUID, TEXT, BOOLEAN) IS
  'Člověk přidá nebo sundá album. AI nevolá.';
COMMENT ON FUNCTION public.place_documento_ai(UUID, UUID, TEXT) IS
  'Jistý classify z extractu. Když už je lidské album, no-op. Desku nepisuje.';

-- Zpětně: dnešní bloque_id = jedno album, finca z expedientes.
INSERT INTO public.documento_bloques (
  tenant_id, documento_id, bloque_id, tipo, source, created_at
)
SELECT d.tenant_id, d.id, d.bloque_id, d.tipo, 'human', d.created_at
  FROM public.documentos d
 WHERE d.deleted_at IS NULL
   AND d.bloque_id IS NOT NULL
   AND NOT EXISTS (
     SELECT 1 FROM public.documento_bloques x
      WHERE x.documento_id = d.id
        AND x.bloque_id = d.bloque_id
        AND x.deleted_at IS NULL
   );

UPDATE public.documentos d
   SET inmueble_id = e.inmueble_id
  FROM public.bloques b
  JOIN public.expedientes e ON e.id = b.expediente_id
 WHERE d.bloque_id = b.id
   AND d.deleted_at IS NULL
   AND d.inmueble_id IS NULL
   AND e.inmueble_id IS NOT NULL;
