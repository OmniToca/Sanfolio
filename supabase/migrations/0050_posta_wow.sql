-- Třídírna k ukázce: zapsáno, HTML, podpis, bounce, paměť bloku, hledání, realtime.
-- Stav done není nový enum (ADD VALUE nejde použít v téže transakci) — done_at.

ALTER TABLE public.tenant_settings
  ADD COLUMN IF NOT EXISTS office_phone TEXT NOT NULL DEFAULT '';

COMMENT ON COLUMN public.tenant_settings.office_phone IS
  'Telefon v podpisu odchozí výzvy. Gestor ho vyplní v Nastavení.';

ALTER TABLE public.posta_messages
  ADD COLUMN IF NOT EXISTS body_html TEXT,
  ADD COLUMN IF NOT EXISTS done_at TIMESTAMPTZ;

COMMENT ON COLUMN public.posta_messages.body_html IS
  'HTML tělo pro čitelný náhled. Webhook AI sem nezapisuje výběr bloku.';
COMMENT ON COLUMN public.posta_messages.done_at IS
  'Gestor označil mail jako zapsaný. Zmizí z fronty, na kartě zůstane. Není ignored.';

CREATE INDEX IF NOT EXISTS idx_posta_messages_done
  ON public.posta_messages (tenant_id, done_at DESC)
  WHERE deleted_at IS NULL AND done_at IS NOT NULL;

ALTER TABLE public.mensajes
  ADD COLUMN IF NOT EXISTS bounce_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS bounce_reason TEXT;

COMMENT ON COLUMN public.mensajes.bounce_at IS
  'Resend nedoručil výzvu. status zůstane sent — stalo se odeslání, ne doručení.';
COMMENT ON COLUMN public.mensajes.bounce_reason IS
  'Krátký důvod bounce od poskytovatele. Bez těla mailu.';

CREATE INDEX IF NOT EXISTS idx_mensajes_bounce
  ON public.mensajes (tenant_id, bounce_at DESC)
  WHERE deleted_at IS NULL AND bounce_at IS NOT NULL;

ALTER TABLE public.posta_senders
  ADD COLUMN IF NOT EXISTS template_key TEXT;

COMMENT ON COLUMN public.posta_senders.template_key IS
  'Poslední blok desky, kam gestor z této adresy uložil přílohu. Návrh, ne auto-save.';

CREATE TABLE IF NOT EXISTS public.posta_sender_domains (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID NOT NULL REFERENCES public.tenants (id),
  domain        TEXT NOT NULL,
  template_key  TEXT NOT NULL,
  created_by    UUID REFERENCES public.profiles (id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at    TIMESTAMPTZ,
  CONSTRAINT posta_sender_domains_ok CHECK (
    domain ~ '^[a-z0-9.-]+\.[a-z]{2,}$'
    AND char_length(domain) BETWEEN 3 AND 200
  )
);

COMMENT ON TABLE public.posta_sender_domains IS
  'Firemní doména odesílatele → blok (iberdrola.es = luz). Gmail sem nepatří. AI nezapisuje.';

CREATE UNIQUE INDEX uq_posta_sender_domains_live
  ON public.posta_sender_domains (tenant_id, domain)
  WHERE deleted_at IS NULL;

CREATE TRIGGER trg_posta_sender_domains_updated
  BEFORE UPDATE ON public.posta_sender_domains
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_posta_sender_domains_no_hard_delete
  BEFORE DELETE ON public.posta_sender_domains
  FOR EACH ROW EXECUTE FUNCTION public.forbid_hard_delete();
CREATE TRIGGER trg_posta_sender_domains_audit
  AFTER INSERT OR UPDATE ON public.posta_sender_domains
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();

ALTER TABLE public.posta_sender_domains ENABLE ROW LEVEL SECURITY;

CREATE POLICY posta_sender_domains_select ON public.posta_sender_domains
  FOR SELECT TO authenticated
  USING (public.can_access_tenant(tenant_id));

GRANT SELECT ON TABLE public.posta_sender_domains TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.posta_sender_domains TO service_role;

CREATE INDEX IF NOT EXISTS idx_posta_messages_fts
  ON public.posta_messages
  USING gin (
    to_tsvector(
      'simple',
      coalesce(subject, '') || ' ' ||
      coalesce(body_text, '') || ' ' ||
      coalesce(from_address, '') || ' ' ||
      coalesce(from_name, '')
    )
  )
  WHERE deleted_at IS NULL;

-- Realtime: otevřená /posta se hýbe bez refreshe.
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.posta_messages;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.posta_attachments;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.mensajes;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END $$;

CREATE OR REPLACE FUNCTION public.remember_posta_sender_block(
  p_tenant_id UUID,
  p_email TEXT,
  p_template_key TEXT,
  p_domain TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT := public.posta_normalize_email(p_email);
  v_key TEXT := lower(btrim(coalesce(p_template_key, '')));
  v_domain TEXT := lower(btrim(coalesce(p_domain, '')));
BEGIN
  IF v_email IS NULL OR v_key = '' THEN
    RETURN;
  END IF;
  IF auth.uid() IS NOT NULL AND NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.posta_senders
     SET template_key = v_key,
         updated_at = now()
   WHERE tenant_id = p_tenant_id
     AND email = v_email
     AND deleted_at IS NULL;

  IF v_domain = '' OR v_domain NOT LIKE '%.%' THEN
    RETURN;
  END IF;
  -- Soukromé schránky (gmail…) sem nepatří — jedna doména ≠ jeden blok.
  IF v_domain IN (
    'gmail.com', 'googlemail.com', 'outlook.com', 'hotmail.com',
    'live.com', 'msn.com', 'icloud.com', 'me.com', 'mac.com',
    'yahoo.com', 'yahoo.es', 'ymail.com', 'proton.me', 'protonmail.com',
    'seznam.cz', 'email.cz', 'post.cz', 'centrum.cz', 'volny.cz',
    'zoznam.sk', 'azet.sk', 'wp.pl', 'o2.pl', 'libero.it',
    'gmx.com', 'gmx.de', 'web.de', 't-online.de', 'orange.fr',
    'free.fr', 'laposte.net', 'wanadoo.fr'
  ) THEN
    RETURN;
  END IF;

  INSERT INTO public.posta_sender_domains (
    tenant_id, domain, template_key, created_by
  ) VALUES (
    p_tenant_id, v_domain, v_key, auth.uid()
  )
  ON CONFLICT (tenant_id, domain) WHERE deleted_at IS NULL
  DO UPDATE SET
    template_key = EXCLUDED.template_key,
    updated_at = now();
END;
$$;

GRANT EXECUTE ON FUNCTION public.remember_posta_sender_block(UUID, TEXT, TEXT, TEXT)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.remember_posta_sender_block(UUID, TEXT, TEXT, TEXT)
  TO service_role;

CREATE OR REPLACE FUNCTION public.suggest_posta_sender_block(
  p_tenant_id UUID,
  p_email TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT := public.posta_normalize_email(p_email);
  v_key TEXT;
  v_domain TEXT;
BEGIN
  IF v_email IS NULL THEN
    RETURN NULL;
  END IF;
  IF auth.uid() IS NOT NULL AND NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT s.template_key INTO v_key
    FROM public.posta_senders s
   WHERE s.tenant_id = p_tenant_id
     AND s.email = v_email
     AND s.deleted_at IS NULL
     AND s.template_key IS NOT NULL
   LIMIT 1;
  IF v_key IS NOT NULL AND btrim(v_key) <> '' THEN
    RETURN v_key;
  END IF;

  v_domain := split_part(v_email, '@', 2);
  IF v_domain = '' THEN
    RETURN NULL;
  END IF;
  SELECT d.template_key INTO v_key
    FROM public.posta_sender_domains d
   WHERE d.tenant_id = p_tenant_id
     AND d.domain = v_domain
     AND d.deleted_at IS NULL
   LIMIT 1;
  RETURN NULLIF(btrim(coalesce(v_key, '')), '');
END;
$$;

GRANT EXECUTE ON FUNCTION public.suggest_posta_sender_block(UUID, TEXT)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_posta_done(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_m RECORD;
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
  IF v_m.cliente_id IS NULL THEN
    RAISE EXCEPTION 'need_cliente';
  END IF;

  UPDATE public.posta_messages
     SET done_at = now(),
         status = 'assigned',
         updated_at = now()
   WHERE id = v_m.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_posta_done(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_posta_undone(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_m RECORD;
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

  UPDATE public.posta_messages
     SET done_at = NULL,
         updated_at = now()
   WHERE id = v_m.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_posta_undone(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_mensaje_bounce(
  p_provider_id TEXT,
  p_reason TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id TEXT := btrim(coalesce(p_provider_id, ''));
  v_n INT := 0;
BEGIN
  IF v_id = '' THEN
    RETURN false;
  END IF;
  UPDATE public.mensajes
     SET bounce_at = now(),
         bounce_reason = NULLIF(left(btrim(coalesce(p_reason, '')), 400), ''),
         updated_at = now()
   WHERE provider_message_id = v_id
     AND deleted_at IS NULL
     AND bounce_at IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_mensaje_bounce(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_mensaje_bounce(TEXT, TEXT) TO service_role;

CREATE OR REPLACE FUNCTION public.posta_bounce_count(p_tenant_id UUID)
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
    FROM public.mensajes m
   WHERE m.tenant_id = p_tenant_id
     AND m.deleted_at IS NULL
     AND m.bounce_at IS NOT NULL
     AND m.status = 'sent';
  RETURN COALESCE(v_n, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.posta_bounce_count(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.search_posta(
  p_tenant_id UUID,
  p_q TEXT,
  p_limit INT DEFAULT 40
)
RETURNS TABLE (message_id UUID)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_q TEXT := btrim(coalesce(p_q, ''));
  v_like TEXT;
  v_ts tsquery;
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF char_length(v_q) < 2 THEN
    RETURN;
  END IF;
  v_like := '%' || v_q || '%';
  BEGIN
    v_ts := websearch_to_tsquery('simple', v_q);
  EXCEPTION WHEN OTHERS THEN
    v_ts := NULL;
  END;

  RETURN QUERY
  SELECT m.id
    FROM public.posta_messages m
    LEFT JOIN public.clientes c
      ON c.id = m.cliente_id AND c.deleted_at IS NULL
   WHERE m.tenant_id = p_tenant_id
     AND m.deleted_at IS NULL
     AND m.status <> 'ignored'
     AND (
       m.from_address ILIKE v_like
       OR coalesce(m.from_name, '') ILIKE v_like
       OR coalesce(m.subject, '') ILIKE v_like
       OR coalesce(m.body_text, '') ILIKE v_like
       OR coalesce(c.nombre, '') ILIKE v_like
       OR coalesce(c.apellidos, '') ILIKE v_like
       OR coalesce(c.razon_social, '') ILIKE v_like
       OR coalesce(c.email, '') ILIKE v_like
       OR (
         v_ts IS NOT NULL
         AND v_ts <> ''::tsquery
         AND to_tsvector(
           'simple',
           coalesce(m.subject, '') || ' ' ||
           coalesce(m.body_text, '') || ' ' ||
           coalesce(m.from_address, '') || ' ' ||
           coalesce(m.from_name, '')
         ) @@ v_ts
       )
     )
   ORDER BY m.received_at DESC
   LIMIT LEAST(GREATEST(coalesce(p_limit, 40), 1), 80);
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_posta(UUID, TEXT, INT) TO authenticated;
