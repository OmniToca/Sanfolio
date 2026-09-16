-- Paměť odesílatele, vlákno odpovědi, fronta neuložených příloh.
-- Odeslání z kanceláře zapisuje Message-ID; AI sem neposílá.

ALTER TABLE public.mensajes
  ADD COLUMN IF NOT EXISTS message_id_header TEXT,
  ADD COLUMN IF NOT EXISTS provider_message_id TEXT;

COMMENT ON COLUMN public.mensajes.message_id_header IS
  'RFC Message-ID odchozí výzvy. Odpověď v Poště se sem přilepí.';
COMMENT ON COLUMN public.mensajes.provider_message_id IS
  'ID u Resendu. Záloha, když klient odpoví na jejich Message-ID.';

CREATE INDEX IF NOT EXISTS idx_mensajes_message_id_header
  ON public.mensajes (tenant_id, message_id_header)
  WHERE deleted_at IS NULL AND message_id_header IS NOT NULL;

ALTER TABLE public.posta_messages
  ADD COLUMN IF NOT EXISTS in_reply_to TEXT,
  ADD COLUMN IF NOT EXISTS references_header TEXT,
  ADD COLUMN IF NOT EXISTS mensaje_id UUID REFERENCES public.mensajes (id);

ALTER TABLE public.posta_messages
  DROP CONSTRAINT IF EXISTS posta_match_method_ok;
ALTER TABLE public.posta_messages
  ADD CONSTRAINT posta_match_method_ok CHECK (
    match_method IS NULL
    OR match_method IN (
      'plus_address', 'from_email', 'manual', 'remembered', 'reply_thread'
    )
  );

COMMENT ON COLUMN public.posta_messages.mensaje_id IS
  'Výzva, na kterou klient odpovídá. Gestor ji nevolí — header / plus-adresa.';

CREATE INDEX IF NOT EXISTS idx_posta_messages_mensaje
  ON public.posta_messages (mensaje_id)
  WHERE deleted_at IS NULL AND mensaje_id IS NOT NULL;

CREATE TABLE public.posta_senders (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   UUID NOT NULL REFERENCES public.tenants (id),
  email       TEXT NOT NULL,
  cliente_id  UUID NOT NULL REFERENCES public.clientes (id),
  created_by  UUID REFERENCES public.profiles (id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at  TIMESTAMPTZ,
  CONSTRAINT posta_senders_email_ok CHECK (email ~ '^[^@\s]+@[^@\s]+$')
);

COMMENT ON TABLE public.posta_senders IS
  'From, který gestor jednou přiřadil ke kartě. Další mail odtud spadne na stejného klienta. AI nezapisuje.';

CREATE UNIQUE INDEX uq_posta_senders_email_live
  ON public.posta_senders (tenant_id, email)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_posta_senders_cliente
  ON public.posta_senders (cliente_id)
  WHERE deleted_at IS NULL;

CREATE TRIGGER trg_posta_senders_updated
  BEFORE UPDATE ON public.posta_senders
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_posta_senders_no_hard_delete
  BEFORE DELETE ON public.posta_senders
  FOR EACH ROW EXECUTE FUNCTION public.forbid_hard_delete();
CREATE TRIGGER trg_posta_senders_audit
  AFTER INSERT OR UPDATE ON public.posta_senders
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();

ALTER TABLE public.posta_senders ENABLE ROW LEVEL SECURITY;

CREATE POLICY posta_senders_select ON public.posta_senders
  FOR SELECT TO authenticated
  USING (public.can_access_tenant(tenant_id));

GRANT SELECT ON TABLE public.posta_senders TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.posta_senders TO service_role;

CREATE OR REPLACE FUNCTION public.remember_posta_sender(
  p_tenant_id UUID,
  p_email TEXT,
  p_cliente_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT := public.posta_normalize_email(p_email);
BEGIN
  IF v_email IS NULL THEN
    RETURN;
  END IF;
  IF auth.uid() IS NOT NULL AND NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.clientes c
     WHERE c.id = p_cliente_id
       AND c.tenant_id = p_tenant_id
       AND c.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'cliente_missing';
  END IF;

  INSERT INTO public.posta_senders (
    tenant_id, email, cliente_id, created_by
  ) VALUES (
    p_tenant_id, v_email, p_cliente_id, auth.uid()
  )
  ON CONFLICT (tenant_id, email) WHERE deleted_at IS NULL
  DO UPDATE SET
    cliente_id = EXCLUDED.cliente_id,
    updated_at = now();
END;
$$;

GRANT EXECUTE ON FUNCTION public.remember_posta_sender(UUID, TEXT, UUID)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.remember_posta_sender(UUID, TEXT, UUID)
  TO service_role;

-- Unique From na kartě / kontaktu, nebo zapamatovaný odesílatel.
CREATE OR REPLACE FUNCTION public.match_posta_cliente(
  p_tenant_id UUID,
  p_email TEXT
)
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT := public.posta_normalize_email(p_email);
  v_id UUID;
  v_n INT;
BEGIN
  IF v_email IS NULL THEN
    RETURN NULL;
  END IF;
  IF auth.uid() IS NOT NULL AND NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT s.cliente_id INTO v_id
    FROM public.posta_senders s
   WHERE s.tenant_id = p_tenant_id
     AND s.email = v_email
     AND s.deleted_at IS NULL
   LIMIT 1;
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  SELECT COUNT(DISTINCT x.cliente_id), MIN(x.cliente_id)
    INTO v_n, v_id
    FROM (
      SELECT c.id AS cliente_id
        FROM public.clientes c
       WHERE c.tenant_id = p_tenant_id
         AND c.deleted_at IS NULL
         AND public.posta_normalize_email(c.email) = v_email
      UNION
      SELECT cc.cliente_id
        FROM public.client_contacts cc
       WHERE cc.tenant_id = p_tenant_id
         AND cc.deleted_at IS NULL
         AND public.posta_normalize_email(cc.email) = v_email
    ) x;

  IF v_n = 1 THEN
    RETURN v_id;
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.suggest_posta_cliente(
  p_tenant_id UUID,
  p_email TEXT,
  p_from_name TEXT DEFAULT NULL
)
RETURNS TABLE (
  cliente_id UUID,
  nombre TEXT,
  match_method TEXT,
  auto BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT := public.posta_normalize_email(p_email);
  v_id UUID;
  v_method TEXT;
  v_auto BOOLEAN := false;
  v_name TEXT := lower(btrim(coalesce(p_from_name, '')));
  v_n INT;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF v_email IS NOT NULL THEN
    SELECT s.cliente_id INTO v_id
      FROM public.posta_senders s
     WHERE s.tenant_id = p_tenant_id
       AND s.email = v_email
       AND s.deleted_at IS NULL
     LIMIT 1;
    IF v_id IS NOT NULL THEN
      v_method := 'remembered';
      v_auto := true;
    ELSE
      v_id := public.match_posta_cliente(p_tenant_id, v_email);
      IF v_id IS NOT NULL THEN
        v_method := 'from_email';
        v_auto := true;
      END IF;
    END IF;
  END IF;

  IF v_id IS NULL AND char_length(v_name) >= 5 THEN
    SELECT COUNT(*)::INT, MIN(c.id)
      INTO v_n, v_id
      FROM public.clientes c
     WHERE c.tenant_id = p_tenant_id
       AND c.deleted_at IS NULL
       AND (
         lower(btrim(concat_ws(' ', c.nombre, c.apellidos))) = v_name
         OR lower(btrim(concat_ws(' ', c.apellidos, c.nombre))) = v_name
         OR lower(btrim(coalesce(c.razon_social, ''))) = v_name
       );
    IF v_n = 1 AND v_id IS NOT NULL THEN
      v_method := 'from_name';
      v_auto := false;
    ELSE
      v_id := NULL;
    END IF;
  END IF;

  IF v_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    c.id,
    COALESCE(
      NULLIF(btrim(c.razon_social), ''),
      NULLIF(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''),
      '—'
    ),
    v_method,
    v_auto
  FROM public.clientes c
  WHERE c.id = v_id
    AND c.deleted_at IS NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.suggest_posta_cliente(UUID, TEXT, TEXT)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.suggest_posta_cliente(UUID, TEXT, TEXT)
  TO service_role;

CREATE OR REPLACE FUNCTION public.assign_posta_message(
  p_message_id UUID,
  p_cliente_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_m RECORD;
  v_c RECORD;
BEGIN
  SELECT * INTO v_m
    FROM public.posta_messages
   WHERE id = p_message_id
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_m.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT id, tenant_id INTO v_c
    FROM public.clientes
   WHERE id = p_cliente_id
     AND deleted_at IS NULL;
  IF NOT FOUND OR v_c.tenant_id <> v_m.tenant_id THEN
    RAISE EXCEPTION 'cliente_missing';
  END IF;

  UPDATE public.posta_messages
     SET cliente_id = p_cliente_id,
         status = 'assigned',
         match_method = 'manual',
         updated_at = now()
   WHERE id = v_m.id;

  PERFORM public.remember_posta_sender(
    v_m.tenant_id, v_m.from_address, p_cliente_id
  );
END;
$$;

-- Odpověď na výzvu: In-Reply-To / References → mensajes + karta.
CREATE OR REPLACE FUNCTION public.link_posta_reply(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_m RECORD;
  v_msg RECORD;
  v_hay TEXT;
BEGIN
  SELECT * INTO v_m
    FROM public.posta_messages
   WHERE id = p_message_id
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  v_hay := concat_ws(
    ' ',
    coalesce(v_m.in_reply_to, ''),
    coalesce(v_m.references_header, '')
  );
  IF btrim(v_hay) = '' THEN
    RETURN;
  END IF;

  SELECT x.* INTO v_msg
    FROM public.mensajes x
   WHERE x.tenant_id = v_m.tenant_id
     AND x.deleted_at IS NULL
     AND x.status = 'sent'
     AND x.canal = 'email'
     AND (
       (
         x.message_id_header IS NOT NULL
         AND v_hay ILIKE '%' || x.message_id_header || '%'
       )
       OR (
         x.provider_message_id IS NOT NULL
         AND v_hay ILIKE '%' || x.provider_message_id || '%'
       )
     )
   ORDER BY x.sent_at DESC NULLS LAST
   LIMIT 1;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  UPDATE public.posta_messages
     SET mensaje_id = v_msg.id,
         cliente_id = COALESCE(cliente_id, v_msg.cliente_id),
         status = CASE
           WHEN COALESCE(cliente_id, v_msg.cliente_id) IS NOT NULL
             THEN 'assigned'::public.posta_status
           ELSE status
         END,
         match_method = COALESCE(match_method, 'reply_thread'),
         updated_at = now()
   WHERE id = v_m.id;
END;
$$;

REVOKE ALL ON FUNCTION public.link_posta_reply(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.link_posta_reply(UUID) TO service_role;

CREATE OR REPLACE FUNCTION public.posta_unfiled_count(p_tenant_id UUID)
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
    FROM public.posta_messages m
   WHERE m.tenant_id = p_tenant_id
     AND m.deleted_at IS NULL
     AND m.status = 'assigned'
     AND EXISTS (
       SELECT 1
         FROM public.posta_attachments a
        WHERE a.message_id = m.id
          AND a.deleted_at IS NULL
          AND a.documento_id IS NULL
     );
  RETURN COALESCE(v_n, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.posta_unfiled_count(UUID) TO authenticated;

-- Gestor po odeslání výzvy z mailu: příchozí a výzva jsou jedno vlákno.
CREATE OR REPLACE FUNCTION public.attach_posta_to_mensaje(
  p_message_id UUID,
  p_mensaje_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_m RECORD;
  v_msg RECORD;
BEGIN
  SELECT * INTO v_m
    FROM public.posta_messages
   WHERE id = p_message_id
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_m.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_msg
    FROM public.mensajes
   WHERE id = p_mensaje_id
     AND deleted_at IS NULL;
  IF NOT FOUND OR v_msg.tenant_id <> v_m.tenant_id THEN
    RAISE EXCEPTION 'mensaje_missing';
  END IF;

  UPDATE public.posta_messages
     SET mensaje_id = p_mensaje_id,
         cliente_id = COALESCE(cliente_id, v_msg.cliente_id),
         status = CASE
           WHEN COALESCE(cliente_id, v_msg.cliente_id) IS NOT NULL
             THEN 'assigned'::public.posta_status
           ELSE status
         END,
         updated_at = now()
   WHERE id = v_m.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.attach_posta_to_mensaje(UUID, UUID)
  TO authenticated;
