-- Příchozí pošta kanceláře: kopie schránky → třídírna → složka.
-- Není to druhý Gmail. `mensajes` zůstávají odchozí výzvy s překladem.
-- Přílohu na blok ukládá gestor, ne webhook a ne AI.

CREATE TYPE posta_status AS ENUM ('unassigned', 'assigned', 'ignored');

CREATE TABLE posta_accounts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants (id),
  ingest_local    TEXT NOT NULL,
  ingest_domain   TEXT NOT NULL DEFAULT 'inbound.sanfolio.app',
  ingest_address  TEXT GENERATED ALWAYS AS (
                    lower(ingest_local || '@' || ingest_domain)
                  ) STORED,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ,
  CONSTRAINT posta_accounts_local_ok CHECK (
    ingest_local ~ '^[a-z0-9][a-z0-9._-]{0,63}$'
  )
);

COMMENT ON TABLE posta_accounts IS
  'Jedna ingest adresa na kancelář. Gmail sem posílá kopii; Reply-To = local+cliente@domain.';

CREATE UNIQUE INDEX uq_posta_accounts_tenant_live
  ON posta_accounts (tenant_id)
  WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_posta_accounts_address_live
  ON posta_accounts (ingest_address)
  WHERE deleted_at IS NULL;

CREATE TABLE posta_messages (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            UUID NOT NULL REFERENCES tenants (id),
  account_id           UUID NOT NULL REFERENCES posta_accounts (id),
  provider_message_id  TEXT NOT NULL,
  message_id_header    TEXT,
  from_address         TEXT NOT NULL,
  from_name            TEXT,
  to_addresses         TEXT[] NOT NULL DEFAULT '{}',
  cc_addresses         TEXT[] NOT NULL DEFAULT '{}',
  subject              TEXT,
  body_text            TEXT,
  received_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  cliente_id           UUID REFERENCES clientes (id),
  match_method         TEXT,
  status               posta_status NOT NULL DEFAULT 'unassigned',
  gmail_url            TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at           TIMESTAMPTZ,
  CONSTRAINT posta_match_method_ok CHECK (
    match_method IS NULL
    OR match_method IN ('plus_address', 'from_email', 'manual')
  )
);

COMMENT ON TABLE posta_messages IS
  'Přijatý mail. status unassigned/assigned/ignored. Soft-delete, žádný Gmail clone.';
COMMENT ON COLUMN posta_messages.match_method IS
  'plus_address / from_email = návrh z webhooku. manual = gestor. AI sem nezapisuje.';

CREATE UNIQUE INDEX uq_posta_messages_provider_live
  ON posta_messages (tenant_id, provider_message_id)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_posta_messages_tenant_status
  ON posta_messages (tenant_id, status, received_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_posta_messages_cliente
  ON posta_messages (cliente_id, received_at DESC)
  WHERE deleted_at IS NULL AND cliente_id IS NOT NULL;

CREATE TABLE posta_attachments (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      UUID NOT NULL REFERENCES tenants (id),
  message_id     UUID NOT NULL REFERENCES posta_messages (id),
  filename       TEXT NOT NULL,
  mime           TEXT,
  byte_size      INT,
  storage_path   TEXT NOT NULL,
  documento_id   UUID REFERENCES documentos (id),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at     TIMESTAMPTZ
);

COMMENT ON TABLE posta_attachments IS
  'Blob v bucketu documentos pod {tenant}/posta/{message}/…. documento_id až gestor uloží do složky.';

CREATE INDEX idx_posta_attachments_message
  ON posta_attachments (message_id)
  WHERE deleted_at IS NULL;

CREATE TRIGGER trg_posta_accounts_updated
  BEFORE UPDATE ON posta_accounts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_posta_messages_updated
  BEFORE UPDATE ON posta_messages
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_posta_attachments_updated
  BEFORE UPDATE ON posta_attachments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_posta_accounts_no_hard_delete
  BEFORE DELETE ON posta_accounts
  FOR EACH ROW EXECUTE FUNCTION forbid_hard_delete();
CREATE TRIGGER trg_posta_messages_no_hard_delete
  BEFORE DELETE ON posta_messages
  FOR EACH ROW EXECUTE FUNCTION forbid_hard_delete();
CREATE TRIGGER trg_posta_attachments_no_hard_delete
  BEFORE DELETE ON posta_attachments
  FOR EACH ROW EXECUTE FUNCTION forbid_hard_delete();

ALTER TABLE posta_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE posta_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE posta_attachments ENABLE ROW LEVEL SECURITY;

CREATE POLICY posta_accounts_select ON posta_accounts
  FOR SELECT TO authenticated
  USING (public.can_access_tenant(tenant_id));
CREATE POLICY posta_messages_select ON posta_messages
  FOR SELECT TO authenticated
  USING (public.can_access_tenant(tenant_id));
CREATE POLICY posta_attachments_select ON posta_attachments
  FOR SELECT TO authenticated
  USING (public.can_access_tenant(tenant_id));

GRANT SELECT ON TABLE public.posta_accounts TO authenticated;
GRANT SELECT ON TABLE public.posta_messages TO authenticated;
GRANT SELECT ON TABLE public.posta_attachments TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.posta_accounts TO service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE public.posta_messages TO service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE public.posta_attachments TO service_role;

-- Body mailu do auditu nepatří (PII + velikost).
CREATE OR REPLACE FUNCTION public.audit_row_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_action TEXT;
  v_before JSONB;
  v_after JSONB;
  v_strip TEXT[] := ARRAY[
    'search_vector', 'updated_at', 'cuerpo', 'translations',
    'body_text', 'body_html'
  ];
  v_imp UUID;
BEGIN
  IF TG_OP = 'UPDATE'
     AND (to_jsonb(NEW) - 'updated_at' - 'search_vector' - 'body_text')
       = (to_jsonb(OLD) - 'updated_at' - 'search_vector' - 'body_text') THEN
    RETURN NEW;
  END IF;

  SELECT s.id INTO v_imp
  FROM support_view_sessions s
  WHERE s.support_user_id = auth.uid()
    AND s.ended_at IS NULL
    AND s.expires_at > now()
  ORDER BY s.started_at DESC
  LIMIT 1;

  IF TG_OP = 'INSERT' THEN
    v_after := to_jsonb(NEW) - v_strip;
    IF TG_TABLE_NAME = 'clientes' THEN
      v_action := 'clientes.insert';
    ELSIF TG_TABLE_NAME = 'mensajes' THEN
      v_action := 'mensajes.' || NEW.status::text;
    ELSIF TG_TABLE_NAME = 'documentos' THEN
      v_action := 'documentos.insert';
    ELSIF TG_TABLE_NAME = 'client_contacts' THEN
      v_action := 'client_contacts.insert';
    ELSIF TG_TABLE_NAME = 'posta_messages' THEN
      v_action := 'posta.insert';
    ELSIF TG_TABLE_NAME = 'posta_attachments' THEN
      v_action := 'posta.attachment_insert';
    ELSE
      v_action := TG_TABLE_NAME || '.insert';
    END IF;
    INSERT INTO audit_logs (
      tenant_id, actor_id, impersonation_session_id,
      action, entity_table, entity_id, after
    ) VALUES (
      NEW.tenant_id, auth.uid(), v_imp, v_action, TG_TABLE_NAME, NEW.id, v_after
    );
    RETURN NEW;
  END IF;

  v_before := to_jsonb(OLD) - v_strip;
  v_after := to_jsonb(NEW) - v_strip;

  IF TG_TABLE_NAME = 'clientes' THEN
    IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
      v_action := 'clientes.soft_delete';
    ELSIF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
      v_action := 'clientes.restore';
    ELSE
      v_action := 'clientes.update';
    END IF;
  ELSIF TG_TABLE_NAME = 'mensajes' THEN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      v_action := 'mensajes.' || NEW.status::text;
    ELSE
      v_action := 'mensajes.update';
    END IF;
  ELSIF TG_TABLE_NAME = 'posta_messages' THEN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      v_action := 'posta.' || NEW.status::text;
    ELSIF NEW.cliente_id IS DISTINCT FROM OLD.cliente_id THEN
      v_action := 'posta.assigned';
    ELSE
      v_action := 'posta.update';
    END IF;
  ELSIF TG_TABLE_NAME = 'posta_attachments' THEN
    IF OLD.documento_id IS NULL AND NEW.documento_id IS NOT NULL THEN
      v_action := 'posta.filed';
    ELSIF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
      v_action := 'posta.attachment_soft_delete';
    ELSE
      v_action := 'posta.attachment_update';
    END IF;
  ELSIF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
    v_action := TG_TABLE_NAME || '.soft_delete';
  ELSE
    v_action := TG_TABLE_NAME || '.update';
  END IF;

  INSERT INTO audit_logs (
    tenant_id, actor_id, impersonation_session_id,
    action, entity_table, entity_id, before, after
  ) VALUES (
    NEW.tenant_id, auth.uid(), v_imp, v_action, TG_TABLE_NAME, NEW.id, v_before, v_after
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_posta_messages_audit
  AFTER INSERT OR UPDATE ON posta_messages
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();

CREATE TRIGGER trg_posta_attachments_audit
  AFTER INSERT OR UPDATE ON posta_attachments
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();

-- ---------------------------------------------------------------------------
-- Seed ingest adresy při vzniku kanceláře.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.seed_posta_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_local TEXT := 'p' || substring(replace(NEW.id::text, '-', ''), 1, 8);
BEGIN
  BEGIN
    INSERT INTO posta_accounts (tenant_id, ingest_local)
    VALUES (NEW.id, v_local);
  EXCEPTION WHEN unique_violation THEN
    INSERT INTO posta_accounts (tenant_id, ingest_local)
    VALUES (NEW.id, 'p' || replace(NEW.id::text, '-', ''));
  END;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_tenants_seed_posta
  AFTER INSERT ON tenants
  FOR EACH ROW EXECUTE FUNCTION public.seed_posta_account();

INSERT INTO posta_accounts (tenant_id, ingest_local)
SELECT t.id, 'p' || substring(replace(t.id::text, '-', ''), 1, 8)
FROM tenants t
WHERE t.deleted_at IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM posta_accounts a
    WHERE a.tenant_id = t.id AND a.deleted_at IS NULL
  );

CREATE OR REPLACE FUNCTION public.ensure_posta_account(p_tenant_id UUID)
RETURNS TABLE (
  id UUID,
  ingest_local TEXT,
  ingest_domain TEXT,
  ingest_address TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  INSERT INTO posta_accounts (tenant_id, ingest_local)
  VALUES (
    p_tenant_id,
    'p' || substring(replace(p_tenant_id::text, '-', ''), 1, 8)
  )
  ON CONFLICT (tenant_id) WHERE deleted_at IS NULL DO NOTHING;

  RETURN QUERY
  SELECT a.id, a.ingest_local, a.ingest_domain, a.ingest_address
  FROM posta_accounts a
  WHERE a.tenant_id = p_tenant_id
    AND a.deleted_at IS NULL
  LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_posta_account(UUID) TO authenticated;

COMMENT ON FUNCTION public.ensure_posta_account(UUID) IS
  'Vrátí ingest adresu kanceláře. Založí ji, když chybí (starý tenant).';

-- Normalizovaný e-mail z "Jméno <x@y>" i holého x@y.
CREATE OR REPLACE FUNCTION public.posta_normalize_email(p_raw TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(
    lower(trim(both FROM
      COALESCE(
        substring(p_raw FROM '<([^>]+)>'),
        p_raw
      )
    )),
    ''
  );
$$;

GRANT EXECUTE ON FUNCTION public.posta_normalize_email(TEXT) TO authenticated;

-- Plus-tag za ingest_local. UUID klienta, jinak NULL.
CREATE OR REPLACE FUNCTION public.posta_plus_cliente_id(p_address TEXT)
RETURNS UUID
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_email TEXT := public.posta_normalize_email(p_address);
  v_local TEXT;
  v_tag TEXT;
BEGIN
  IF v_email IS NULL OR position('@' IN v_email) = 0 THEN
    RETURN NULL;
  END IF;
  v_local := split_part(v_email, '@', 1);
  IF position('+' IN v_local) = 0 THEN
    RETURN NULL;
  END IF;
  v_tag := substring(v_local FROM position('+' IN v_local) + 1);
  IF v_tag ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    RETURN v_tag::uuid;
  END IF;
  RETURN NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.posta_plus_cliente_id(TEXT) TO authenticated;

-- Webhook: která kancelář a případně který klient (plus-adresa).
CREATE OR REPLACE FUNCTION public.resolve_posta_recipient(p_address TEXT)
RETURNS TABLE (
  tenant_id UUID,
  account_id UUID,
  cliente_id UUID
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT := public.posta_normalize_email(p_address);
  v_local TEXT;
  v_domain TEXT;
  v_base TEXT;
  v_plus UUID;
  v_acc RECORD;
BEGIN
  IF v_email IS NULL OR position('@' IN v_email) = 0 THEN
    RETURN;
  END IF;
  v_local := split_part(v_email, '@', 1);
  v_domain := split_part(v_email, '@', 2);
  v_base := split_part(v_local, '+', 1);
  v_plus := public.posta_plus_cliente_id(v_email);

  SELECT a.id, a.tenant_id
    INTO v_acc
    FROM posta_accounts a
   WHERE a.deleted_at IS NULL
     AND (
       a.ingest_address = v_email
       OR (a.ingest_local = v_base AND lower(a.ingest_domain) = v_domain)
     )
   LIMIT 1;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF v_plus IS NOT NULL
     AND EXISTS (
       SELECT 1 FROM clientes c
        WHERE c.id = v_plus
          AND c.tenant_id = v_acc.tenant_id
          AND c.deleted_at IS NULL
     ) THEN
    tenant_id := v_acc.tenant_id;
    account_id := v_acc.id;
    cliente_id := v_plus;
    RETURN NEXT;
    RETURN;
  END IF;

  tenant_id := v_acc.tenant_id;
  account_id := v_acc.id;
  cliente_id := NULL;
  RETURN NEXT;
END;
$$;

-- Edge volá service_role. Authenticated nesmí enumerovat cizí ingest.
REVOKE ALL ON FUNCTION public.resolve_posta_recipient(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_posta_recipient(TEXT) TO service_role;

-- Přesně jedna karta se stejným e-mailem (klient nebo druhý kontakt).
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

  SELECT COUNT(DISTINCT x.cliente_id), MIN(x.cliente_id)
    INTO v_n, v_id
    FROM (
      SELECT c.id AS cliente_id
        FROM clientes c
       WHERE c.tenant_id = p_tenant_id
         AND c.deleted_at IS NULL
         AND public.posta_normalize_email(c.email) = v_email
      UNION
      SELECT cc.cliente_id
        FROM client_contacts cc
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

GRANT EXECUTE ON FUNCTION public.match_posta_cliente(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.match_posta_cliente(UUID, TEXT) TO service_role;

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
    FROM posta_messages
   WHERE id = p_message_id
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_m.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT id, tenant_id INTO v_c
    FROM clientes
   WHERE id = p_cliente_id
     AND deleted_at IS NULL;
  IF NOT FOUND OR v_c.tenant_id <> v_m.tenant_id THEN
    RAISE EXCEPTION 'cliente_missing';
  END IF;

  UPDATE posta_messages
     SET cliente_id = p_cliente_id,
         status = 'assigned',
         match_method = 'manual',
         updated_at = now()
   WHERE id = v_m.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.assign_posta_message(UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.ignore_posta_message(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_m RECORD;
BEGIN
  SELECT * INTO v_m
    FROM posta_messages
   WHERE id = p_message_id
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_m.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE posta_messages
     SET status = 'ignored',
         updated_at = now()
   WHERE id = v_m.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ignore_posta_message(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.unassign_posta_message(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_m RECORD;
BEGIN
  SELECT * INTO v_m
    FROM posta_messages
   WHERE id = p_message_id
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_m.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE posta_messages
     SET cliente_id = NULL,
         status = 'unassigned',
         match_method = NULL,
         updated_at = now()
   WHERE id = v_m.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.unassign_posta_message(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_posta_attachment_filed(
  p_attachment_id UUID,
  p_documento_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_a RECORD;
  v_m RECORD;
  v_d RECORD;
BEGIN
  SELECT * INTO v_a
    FROM posta_attachments
   WHERE id = p_attachment_id
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_a.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_m
    FROM posta_messages
   WHERE id = v_a.message_id
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF v_m.cliente_id IS NULL THEN
    RAISE EXCEPTION 'unassigned';
  END IF;

  SELECT id, tenant_id, cliente_id INTO v_d
    FROM documentos
   WHERE id = p_documento_id
     AND deleted_at IS NULL;
  IF NOT FOUND
     OR v_d.tenant_id <> v_a.tenant_id
     OR v_d.cliente_id IS DISTINCT FROM v_m.cliente_id THEN
    RAISE EXCEPTION 'documento_mismatch';
  END IF;

  UPDATE posta_attachments
     SET documento_id = p_documento_id,
         updated_at = now()
   WHERE id = v_a.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_posta_attachment_filed(UUID, UUID) TO authenticated;

-- Badge v inboxu: nepřiřazené maily, které mají přílohu.
CREATE OR REPLACE FUNCTION public.posta_unassigned_attachment_count(
  p_tenant_id UUID
)
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
    FROM posta_messages m
   WHERE m.tenant_id = p_tenant_id
     AND m.deleted_at IS NULL
     AND m.status = 'unassigned'
     AND EXISTS (
       SELECT 1 FROM posta_attachments a
        WHERE a.message_id = m.id
          AND a.deleted_at IS NULL
     );
  RETURN COALESCE(v_n, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.posta_unassigned_attachment_count(UUID) TO authenticated;
