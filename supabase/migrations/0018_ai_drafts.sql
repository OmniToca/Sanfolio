-- Návrhy AI. TTL 24 h. AI sem zapisuje; clientes/bloques jen gestor Guardar.

CREATE TABLE ai_conversations (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    UUID NOT NULL REFERENCES tenants (id),
  created_by   UUID REFERENCES profiles (id),
  locale       TEXT NOT NULL DEFAULT 'es',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at   TIMESTAMPTZ
);

CREATE TABLE ai_messages (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         UUID NOT NULL REFERENCES tenants (id),
  conversation_id   UUID NOT NULL REFERENCES ai_conversations (id),
  role              TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'tool')),
  content           TEXT,
  tool_name         TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at        TIMESTAMPTZ
);

CREATE TABLE ai_drafts (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      UUID NOT NULL REFERENCES tenants (id),
  cliente_id     UUID REFERENCES clientes (id),
  created_by     UUID REFERENCES profiles (id),
  purpose        TEXT NOT NULL DEFAULT 'extract_document',
  target         TEXT NOT NULL DEFAULT 'bloque',
  bloque_key     TEXT,
  fields         JSONB NOT NULL DEFAULT '{}',
  enable_blocks  JSONB NOT NULL DEFAULT '[]',
  storage_path   TEXT,
  expires_at     TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '24 hours'),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at     TIMESTAMPTZ
);

CREATE INDEX idx_ai_drafts_cliente_live
  ON ai_drafts (tenant_id, cliente_id, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_ai_conversations_tenant
  ON ai_conversations (tenant_id, created_at DESC)
  WHERE deleted_at IS NULL;

ALTER TABLE ai_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_drafts ENABLE ROW LEVEL SECURITY;

CREATE POLICY ai_conversations_select ON ai_conversations
  FOR SELECT TO authenticated
  USING (public.can_access_tenant(tenant_id));
CREATE POLICY ai_conversations_insert ON ai_conversations
  FOR INSERT TO authenticated
  WITH CHECK (public.can_access_tenant(tenant_id));
CREATE POLICY ai_conversations_update ON ai_conversations
  FOR UPDATE TO authenticated
  USING (public.can_access_tenant(tenant_id))
  WITH CHECK (public.can_access_tenant(tenant_id));

CREATE POLICY ai_messages_select ON ai_messages
  FOR SELECT TO authenticated
  USING (public.can_access_tenant(tenant_id));
CREATE POLICY ai_messages_insert ON ai_messages
  FOR INSERT TO authenticated
  WITH CHECK (public.can_access_tenant(tenant_id));
CREATE POLICY ai_messages_update ON ai_messages
  FOR UPDATE TO authenticated
  USING (public.can_access_tenant(tenant_id))
  WITH CHECK (public.can_access_tenant(tenant_id));

CREATE POLICY ai_drafts_select ON ai_drafts
  FOR SELECT TO authenticated
  USING (public.can_access_tenant(tenant_id));
CREATE POLICY ai_drafts_insert ON ai_drafts
  FOR INSERT TO authenticated
  WITH CHECK (public.can_access_tenant(tenant_id));
CREATE POLICY ai_drafts_update ON ai_drafts
  FOR UPDATE TO authenticated
  USING (public.can_access_tenant(tenant_id))
  WITH CHECK (public.can_access_tenant(tenant_id));

CREATE TRIGGER trg_ai_conversations_updated
  BEFORE UPDATE ON ai_conversations
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_ai_drafts_updated
  BEFORE UPDATE ON ai_drafts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_ai_conversations_no_hard_delete
  BEFORE DELETE ON ai_conversations
  FOR EACH ROW EXECUTE FUNCTION forbid_hard_delete();
CREATE TRIGGER trg_ai_messages_no_hard_delete
  BEFORE DELETE ON ai_messages
  FOR EACH ROW EXECUTE FUNCTION forbid_hard_delete();
CREATE TRIGGER trg_ai_drafts_no_hard_delete
  BEFORE DELETE ON ai_drafts
  FOR EACH ROW EXECUTE FUNCTION forbid_hard_delete();

GRANT EXECUTE ON FUNCTION public.can_access_tenant(UUID) TO authenticated;

COMMENT ON TABLE ai_drafts IS
  'Návrh AI (TTL 24 h). Guardar je akce člověka, ne modelu.';
