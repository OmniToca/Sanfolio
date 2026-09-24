-- AI prose shrnutí papíru v jazyku staff UI. Není extracted / caption —
-- jen glance na kartě stohu. Guardar desky to nepřepisuje; AI sem smí.

ALTER TABLE public.documentos
  ADD COLUMN IF NOT EXISTS ai_summary text,
  ADD COLUMN IF NOT EXISTS ai_summary_locale text;

COMMENT ON COLUMN public.documentos.ai_summary IS
  '1–2 věty o papíru v jazyku staff (profiles.locale). Extract zapisuje; Guardar desky nemění.';
COMMENT ON COLUMN public.documentos.ai_summary_locale IS
  'Locale, ve kterém vzniklo ai_summary (cs/en/es/de/fr).';

-- GDPR: summary může mít jméno / NIE. Doplníme clear do anonymize.
CREATE OR REPLACE FUNCTION public.anonymize_cliente(p_cliente_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  c RECORD;
  d RECORD;
BEGIN
  SELECT * INTO c FROM clientes WHERE id = p_cliente_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.is_tenant_owner(c.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF public.cliente_has_legal_hold(c.id) THEN
    RAISE EXCEPTION 'legal_hold';
  END IF;

  UPDATE clientes SET
    erasure_requested_at = coalesce(erasure_requested_at, now()),
    nombre = 'ANON',
    apellidos = NULL,
    razon_social = CASE WHEN kind = 'empresa' THEN 'ANON' ELSE razon_social END,
    email = NULL,
    tel = NULL,
    direccion = NULL,
    iban = NULL,
    notas = NULL,
    updated_at = now()
  WHERE id = c.id;

  UPDATE client_identifiers SET
    deleted_at = coalesce(deleted_at, now()),
    updated_at = now()
  WHERE cliente_id = c.id
    AND deleted_at IS NULL;

  PERFORM set_config('storage.allow_delete_query', 'true', true);

  FOR d IN
    SELECT * FROM documentos
     WHERE cliente_id = c.id
       AND storage_purged_at IS NULL
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM documentos x
      WHERE x.storage_path = d.storage_path
        AND x.id <> d.id
        AND x.storage_purged_at IS NULL
        AND x.cliente_id <> c.id
    ) THEN
      DELETE FROM storage.objects
      WHERE bucket_id = 'documentos'
        AND name = d.storage_path;
    END IF;
  END LOOP;

  UPDATE documentos SET
    extracted = '{}'::jsonb,
    body_text = NULL,
    caption = NULL,
    ai_summary = NULL,
    ai_summary_locale = NULL,
    original_name = 'ANON',
    storage_purged_at = coalesce(storage_purged_at, now()),
    updated_at = now()
  WHERE cliente_id = c.id;

  INSERT INTO audit_logs (
    tenant_id, actor_id, impersonation_session_id,
    action, entity_table, entity_id, after
  ) VALUES (
    c.tenant_id,
    auth.uid(),
    (SELECT s.id FROM support_view_sessions s
      WHERE s.support_user_id = auth.uid()
        AND s.ended_at IS NULL
      ORDER BY s.started_at DESC LIMIT 1),
    'clientes.anonymize',
    'clientes',
    c.id,
    jsonb_build_object('erasure', true)
  );
  RETURN true;
END;
$$;
