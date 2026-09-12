-- Gestoría OS — jádro podle papírové desky.
-- Povinné dokumenty a dny připomínek jsou defaulty; po dotazníku se upraví
-- tabulka bloque_templates / plazo_rules, ne stroj stavů.

-- gen_random_uuid() je v pg_catalog. uuid-ossp na hosted Supabase žije
-- ve schématu extensions, takže uuid_generate_v4() bez prefixu spadne.
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;
SET search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
CREATE TYPE member_role AS ENUM ('owner', 'gestor', 'asistente');
CREATE TYPE cliente_kind AS ENUM ('persona', 'empresa');
CREATE TYPE identifier_kind AS ENUM ('nie', 'dni', 'nif', 'passport', 'nss', 'other');
CREATE TYPE checksum_status AS ENUM ('valid', 'invalid', 'unknown');
CREATE TYPE expediente_tipo AS ENUM (
  'compraventa',
  'suministros_seguros',
  'impuestos_ibi',
  'impuestos_210',
  'impuestos_renta',
  'nie_tramite',
  'poder',
  'policia',
  'ayuntamiento',
  'testament',
  'otros'
);
CREATE TYPE expediente_estado AS ENUM (
  'abierto', 'en_curso', 'espera_cliente', 'espera_admin', 'hecho', 'archivado'
);
CREATE TYPE bloque_status AS ENUM (
  'off', 'missing_data', 'missing_document', 'watching', 'done'
);
CREATE TYPE plazo_source AS ENUM ('derived', 'manual');
CREATE TYPE mensaje_status AS ENUM ('draft', 'sent', 'discarded');
CREATE TYPE provision_kind AS ENUM ('ingreso', 'factura', 'ajuste');

-- ---------------------------------------------------------------------------
-- Identity / tenancy
-- ---------------------------------------------------------------------------
CREATE TABLE tenants (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  locale      TEXT NOT NULL DEFAULT 'es',
  timezone    TEXT NOT NULL DEFAULT 'Europe/Madrid',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at  TIMESTAMPTZ
);

CREATE TABLE profiles (
  id          UUID PRIMARY KEY, -- = auth.uid()
  email       TEXT NOT NULL UNIQUE,
  full_name   TEXT,
  is_support  BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at  TIMESTAMPTZ
);

CREATE TABLE tenant_members (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   UUID NOT NULL REFERENCES tenants (id),
  profile_id  UUID NOT NULL REFERENCES profiles (id),
  role        member_role NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at  TIMESTAMPTZ
);

CREATE UNIQUE INDEX uq_tenant_members_live
  ON tenant_members (tenant_id, profile_id)
  WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- Catalogs (ladí se po odpovědích z kanceláře)
-- ---------------------------------------------------------------------------
CREATE TABLE bloque_templates (
  key                    TEXT PRIMARY KEY,
  label_es               TEXT NOT NULL,
  sort_order             INT NOT NULL,
  required_field_keys    TEXT[] NOT NULL DEFAULT '{}',
  required_doc_types     TEXT[] NOT NULL DEFAULT '{}',
  plazo_kind             TEXT,
  on_compraventa         BOOLEAN NOT NULL DEFAULT true
);

INSERT INTO bloque_templates
  (key, label_es, sort_order, required_field_keys, required_doc_types, plazo_kind, on_compraventa)
VALUES
  ('cliente_snapshot', 'Cliente', 10, '{}', '{}', NULL, true),
  ('escritura', 'Escritura', 20, '{}', '{copia_escritura}', NULL, true),
  ('agua', 'Agua', 30, '{proveedor,numero_contrato,titular}', '{contrato_agua}', NULL, true),
  ('luz', 'Luz', 40, '{proveedor,numero_contrato,titular}', '{contrato_luz}', NULL, true),
  ('gaz', 'Gaz', 50, '{proveedor,numero_contrato,titular}', '{contrato_gaz}', NULL, true),
  ('comunidad', 'Comunidad', 60, '{proveedor,numero_contrato,titular}', '{certificado_comunidad}', NULL, true),
  ('suma', 'SUMA', 70, '{domiciliado}', '{recibo_ibi}', 'ibi_anual', true),
  ('plusvalia', 'Plusvalía', 80, '{}', '{declaracion_plusvalia}', 'plusvalia_plazo', true),
  ('seguro', 'Seguro', 90, '{compania,numero_poliza,fecha_vencimiento}', '{poliza_seguro}', 'seguro_renovacion', true),
  ('provision_factura', 'Provisión de fondos y factura', 100, '{}', '{}', NULL, true),
  ('alarma', 'Alarma', 110, '{compania,numero_contrato,fecha_vencimiento}', '{contrato_alarma}', 'alarma_renovacion', true),
  ('nie_tramite', 'NIE', 120, '{estado_tramite}', '{}', NULL, true),
  ('poder', 'Poder', 130, '{apoderado,fecha_caducidad}', '{copia_poder}', 'poder_caducidad', true),
  ('modelo_210', 'Modelo 210', 200, '{periodicidad,periodo}', '{}', 'modelo_210', false),
  ('renta', 'Renta / IRPF', 210, '{ejercicio}', '{}', 'renta', false);

CREATE TABLE plazo_rules (
  kind          TEXT PRIMARY KEY,
  offset_days   INT[] NOT NULL,
  notes         TEXT
);

INSERT INTO plazo_rules (kind, offset_days, notes) VALUES
  ('plusvalia_plazo', '{14,7,1}', 'Default 30 dní od escritura_fecha — ověřit dotazníkem'),
  ('ibi_anual', '{60,30,7}', 'Default 1.11. — ověřit'),
  ('seguro_renovacion', '{60,30,7}', NULL),
  ('alarma_renovacion', '{60,30,7}', NULL),
  ('poder_caducidad', '{60,30,7}', NULL),
  ('nie_caducidad', '{90,60,30}', NULL),
  ('cita_nie', '{3,1}', NULL),
  ('modelo_210', '{21,7}', 'Ověřit periodicitu'),
  ('renta', '{30,7}', 'Default 30.6. — ověřit');

-- ---------------------------------------------------------------------------
-- Domain
-- ---------------------------------------------------------------------------
CREATE TABLE clientes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants (id),
  kind            cliente_kind NOT NULL DEFAULT 'persona',
  nombre          TEXT,
  apellidos       TEXT,
  razon_social    TEXT,
  email           TEXT,
  tel             TEXT,
  direccion       TEXT,
  iban            TEXT,
  idioma          TEXT NOT NULL DEFAULT 'es',
  notas           TEXT,
  search_vector   TSVECTOR GENERATED ALWAYS AS (
    to_tsvector(
      'simple',
      coalesce(nombre, '') || ' ' ||
      coalesce(apellidos, '') || ' ' ||
      coalesce(razon_social, '') || ' ' ||
      coalesce(email, '') || ' ' ||
      coalesce(tel, '') || ' ' ||
      coalesce(direccion, '')
    )
  ) STORED,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ,
  CONSTRAINT clientes_has_name CHECK (
    (kind = 'persona' AND (nombre IS NOT NULL OR apellidos IS NOT NULL))
    OR (kind = 'empresa' AND razon_social IS NOT NULL)
  )
);

CREATE INDEX idx_clientes_tenant_live ON clientes (tenant_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_clientes_search ON clientes USING gin (search_vector) WHERE deleted_at IS NULL;

CREATE TABLE client_identifiers (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          UUID NOT NULL REFERENCES tenants (id),
  cliente_id         UUID NOT NULL REFERENCES clientes (id),
  kind               identifier_kind NOT NULL,
  value_raw          TEXT NOT NULL,
  value_normalized   TEXT NOT NULL,
  checksum           checksum_status NOT NULL DEFAULT 'unknown',
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at         TIMESTAMPTZ
);

CREATE UNIQUE INDEX uq_client_identifiers_live
  ON client_identifiers (tenant_id, kind, value_normalized)
  WHERE deleted_at IS NULL AND position('*' IN value_normalized) = 0;

CREATE INDEX idx_client_identifiers_normalized
  ON client_identifiers (tenant_id, value_normalized)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_client_identifiers_trgm
  ON client_identifiers USING gin (value_normalized extensions.gin_trgm_ops)
  WHERE deleted_at IS NULL;

CREATE TABLE inmuebles (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            UUID NOT NULL REFERENCES tenants (id),
  cliente_id           UUID NOT NULL REFERENCES clientes (id),
  direccion            TEXT NOT NULL,
  notario              TEXT,
  escritura_fecha      DATE,
  protocolo            TEXT,
  referencia_catastral TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at           TIMESTAMPTZ
);

CREATE INDEX idx_inmuebles_cliente ON inmuebles (cliente_id) WHERE deleted_at IS NULL;

CREATE TABLE expedientes (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID NOT NULL REFERENCES tenants (id),
  cliente_id    UUID NOT NULL REFERENCES clientes (id),
  inmueble_id   UUID REFERENCES inmuebles (id),
  tipo          expediente_tipo NOT NULL,
  estado        expediente_estado NOT NULL DEFAULT 'abierto',
  titulo        TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at    TIMESTAMPTZ
);

CREATE INDEX idx_expedientes_cliente ON expedientes (cliente_id) WHERE deleted_at IS NULL;

CREATE TABLE bloques (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      UUID NOT NULL REFERENCES tenants (id),
  expediente_id  UUID NOT NULL REFERENCES expedientes (id),
  template_key   TEXT NOT NULL REFERENCES bloque_templates (key),
  status         bloque_status NOT NULL DEFAULT 'off',
  fields         JSONB NOT NULL DEFAULT '{}',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at     TIMESTAMPTZ
);

CREATE UNIQUE INDEX uq_bloques_live
  ON bloques (expediente_id, template_key)
  WHERE deleted_at IS NULL;

CREATE TABLE documentos (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      UUID NOT NULL REFERENCES tenants (id),
  cliente_id     UUID REFERENCES clientes (id),
  bloque_id      UUID REFERENCES bloques (id),
  tipo           TEXT NOT NULL,
  storage_path   TEXT NOT NULL,
  original_name  TEXT,
  created_by     UUID REFERENCES profiles (id),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at     TIMESTAMPTZ
);

CREATE TABLE plazos (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      UUID NOT NULL REFERENCES tenants (id),
  bloque_id      UUID REFERENCES bloques (id),
  expediente_id  UUID REFERENCES expedientes (id),
  kind           TEXT NOT NULL,
  due_on         DATE NOT NULL,
  source         plazo_source NOT NULL DEFAULT 'derived',
  completed_at   TIMESTAMPTZ,
  snooze_until   DATE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at     TIMESTAMPTZ
);

CREATE TABLE mensajes (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      UUID NOT NULL REFERENCES tenants (id),
  cliente_id     UUID NOT NULL REFERENCES clientes (id),
  plazo_id       UUID REFERENCES plazos (id),
  bloque_id      UUID REFERENCES bloques (id),
  template_key   TEXT,
  canal          TEXT NOT NULL DEFAULT 'email',
  asunto         TEXT,
  cuerpo         TEXT NOT NULL,
  status         mensaje_status NOT NULL DEFAULT 'draft',
  sent_at        TIMESTAMPTZ,
  created_by     UUID REFERENCES profiles (id),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at     TIMESTAMPTZ
);

CREATE TABLE provision_movements (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      UUID NOT NULL REFERENCES tenants (id),
  expediente_id  UUID NOT NULL REFERENCES expedientes (id),
  kind           provision_kind NOT NULL,
  amount_cents   INT NOT NULL,
  note           TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at     TIMESTAMPTZ
);

CREATE TABLE audit_logs (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id                UUID REFERENCES tenants (id),
  actor_id                 UUID REFERENCES profiles (id),
  impersonation_session_id UUID,
  action                   TEXT NOT NULL,
  entity_table             TEXT,
  entity_id                UUID,
  before                   JSONB,
  after                    JSONB,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_logs_tenant ON audit_logs (tenant_id, created_at DESC);

CREATE TABLE support_view_sessions (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  support_user_id  UUID NOT NULL REFERENCES profiles (id),
  tenant_id        UUID NOT NULL REFERENCES tenants (id),
  access_reason    TEXT NOT NULL,
  access_note      TEXT,
  started_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at       TIMESTAMPTZ NOT NULL,
  ended_at         TIMESTAMPTZ
);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION forbid_hard_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'hard delete forbidden — use deleted_at';
END;
$$;

CREATE OR REPLACE FUNCTION forbid_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'audit_logs is append-only';
END;
$$;

CREATE OR REPLACE FUNCTION public.normalize_id(raw TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT upper(
    regexp_replace(
      regexp_replace(trim(coalesce(raw, '')), '[\s\-\./]', '', 'g'),
      '[•·?#]',
      '*',
      'g'
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.id_mask_match(a TEXT, b TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  i INT;
  ca TEXT;
  cb TEXT;
BEGIN
  IF a IS NULL OR b IS NULL THEN
    RETURN false;
  END IF;
  IF char_length(a) <> char_length(b) THEN
    RETURN false;
  END IF;
  FOR i IN 1..char_length(a) LOOP
    ca := substr(a, i, 1);
    cb := substr(b, i, 1);
    IF ca <> '*' AND cb <> '*' AND ca <> cb THEN
      RETURN false;
    END IF;
  END LOOP;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.auth_is_support_user()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = auth.uid()
      AND p.is_support = true
      AND p.deleted_at IS NULL
  );
$$;

CREATE OR REPLACE FUNCTION public.auth_tenant_ids()
RETURNS UUID[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(array_agg(tm.tenant_id), '{}')
  FROM tenant_members tm
  WHERE tm.profile_id = auth.uid()
    AND tm.deleted_at IS NULL;
$$;

CREATE OR REPLACE FUNCTION public.is_member(_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM tenant_members tm
    WHERE tm.tenant_id = _tenant_id
      AND tm.profile_id = auth.uid()
      AND tm.deleted_at IS NULL
  );
$$;

CREATE OR REPLACE FUNCTION public.current_impersonation_tenant()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT s.tenant_id
  FROM support_view_sessions s
  WHERE s.support_user_id = auth.uid()
    AND s.ended_at IS NULL
    AND s.expires_at > now()
  ORDER BY s.started_at DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.can_access_tenant(_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_member(_tenant_id)
      OR (
        public.auth_is_support_user()
        AND public.current_impersonation_tenant() = _tenant_id
      );
$$;

-- Search: Y123**6E najde Y123456E
CREATE OR REPLACE FUNCTION public.search_clients(p_q TEXT, p_limit INT DEFAULT 20)
RETURNS TABLE (
  cliente_id UUID,
  score INT,
  matched_via TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
  q TEXT := public.normalize_id(p_q);
BEGIN
  RETURN QUERY
  WITH id_hits AS (
    SELECT
      ci.cliente_id,
      CASE
        WHEN ci.value_normalized = q THEN 100
        WHEN public.id_mask_match(ci.value_normalized, q) THEN 90
        WHEN ci.value_normalized % q THEN 60
        ELSE 0
      END AS score,
      CASE
        WHEN ci.value_normalized = q THEN 'id_exact'
        WHEN public.id_mask_match(ci.value_normalized, q) THEN 'id_mask'
        ELSE 'id_trgm'
      END AS matched_via
    FROM client_identifiers ci
    WHERE ci.deleted_at IS NULL
      AND public.can_access_tenant(ci.tenant_id)
      AND (
        ci.value_normalized = q
        OR public.id_mask_match(ci.value_normalized, q)
        OR ci.value_normalized % q
      )
  ),
  fts_hits AS (
    SELECT
      c.id AS cliente_id,
      40 AS score,
      'fts'::TEXT AS matched_via
    FROM clientes c
    WHERE c.deleted_at IS NULL
      AND public.can_access_tenant(c.tenant_id)
      AND c.search_vector @@ plainto_tsquery('simple', coalesce(p_q, ''))
  ),
  combined AS (
    SELECT * FROM id_hits WHERE score > 0
    UNION ALL
    SELECT * FROM fts_hits
  )
  SELECT combined.cliente_id, max(combined.score)::INT, (array_agg(combined.matched_via ORDER BY combined.score DESC))[1]
  FROM combined
  GROUP BY combined.cliente_id
  ORDER BY max(combined.score) DESC
  LIMIT greatest(1, least(coalesce(p_limit, 20), 50));
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_clients(TEXT, INT) TO authenticated;

-- Open compraventa: instance bloků z papíru, všechny off (tužka ještě nebyla)
CREATE OR REPLACE FUNCTION public.seed_compraventa_bloques()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.tipo = 'compraventa' THEN
    INSERT INTO bloques (tenant_id, expediente_id, template_key, status)
    SELECT NEW.tenant_id, NEW.id, t.key, 'off'
    FROM bloque_templates t
    WHERE t.on_compraventa = true
    ORDER BY t.sort_order;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_seed_compraventa_bloques
  AFTER INSERT ON expedientes
  FOR EACH ROW
  EXECUTE FUNCTION public.seed_compraventa_bloques();

CREATE OR REPLACE FUNCTION public.audit_open(
  p_entity_table TEXT,
  p_entity_id UUID,
  p_tenant_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  INSERT INTO audit_logs (tenant_id, actor_id, impersonation_session_id, action, entity_table, entity_id)
  VALUES (
    p_tenant_id,
    auth.uid(),
    (SELECT id FROM support_view_sessions
     WHERE support_user_id = auth.uid() AND ended_at IS NULL AND expires_at > now()
     ORDER BY started_at DESC LIMIT 1),
    p_entity_table || '.open',
    p_entity_table,
    p_entity_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.audit_open(TEXT, UUID, UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'tenants','profiles','tenant_members','clientes','client_identifiers',
    'inmuebles','expedientes','bloques','documentos','plazos','mensajes',
    'provision_movements'
  ]
  LOOP
    EXECUTE format(
      'CREATE TRIGGER trg_%s_updated BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_updated_at()',
      t, t
    );
    EXECUTE format(
      'CREATE TRIGGER trg_%s_no_hard_delete BEFORE DELETE ON %I FOR EACH ROW EXECUTE FUNCTION forbid_hard_delete()',
      t, t
    );
  END LOOP;
END;
$$;

CREATE TRIGGER trg_audit_no_update
  BEFORE UPDATE OR DELETE ON audit_logs
  FOR EACH ROW
  EXECUTE FUNCTION forbid_audit_mutation();

-- New auth user → profile
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO profiles (id, email, full_name)
  VALUES (NEW.id, NEW.email, coalesce(NEW.raw_user_meta_data->>'full_name', ''))
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE client_identifiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE inmuebles ENABLE ROW LEVEL SECURITY;
ALTER TABLE expedientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE bloques ENABLE ROW LEVEL SECURITY;
ALTER TABLE documentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE plazos ENABLE ROW LEVEL SECURITY;
ALTER TABLE mensajes ENABLE ROW LEVEL SECURITY;
ALTER TABLE provision_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_view_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE bloque_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE plazo_rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY bloque_templates_read ON bloque_templates FOR SELECT TO authenticated USING (true);
CREATE POLICY plazo_rules_read ON plazo_rules FOR SELECT TO authenticated USING (true);

CREATE POLICY tenants_select ON tenants
  FOR SELECT TO authenticated
  USING (public.can_access_tenant(id) OR public.auth_is_support_user());

CREATE POLICY profiles_select ON profiles
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR public.auth_is_support_user()
    OR EXISTS (
      SELECT 1 FROM tenant_members me
      JOIN tenant_members other ON other.tenant_id = me.tenant_id
      WHERE me.profile_id = auth.uid()
        AND other.profile_id = profiles.id
        AND me.deleted_at IS NULL
        AND other.deleted_at IS NULL
    )
  );

CREATE POLICY profiles_update_self ON profiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

CREATE POLICY tenant_members_select ON tenant_members
  FOR SELECT TO authenticated
  USING (public.can_access_tenant(tenant_id) OR public.auth_is_support_user());

CREATE POLICY tenant_members_modify ON tenant_members
  FOR INSERT TO authenticated
  WITH CHECK (public.can_access_tenant(tenant_id));

CREATE POLICY tenant_members_update ON tenant_members
  FOR UPDATE TO authenticated
  USING (public.can_access_tenant(tenant_id));

-- Generic tenant isolation for business tables
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'clientes','client_identifiers','inmuebles','expedientes','bloques',
    'documentos','plazos','mensajes','provision_movements'
  ]
  LOOP
    EXECUTE format(
      'CREATE POLICY %I_select ON %I FOR SELECT TO authenticated USING (public.can_access_tenant(tenant_id))',
      t, t
    );
    EXECUTE format(
      'CREATE POLICY %I_insert ON %I FOR INSERT TO authenticated WITH CHECK (public.can_access_tenant(tenant_id))',
      t, t
    );
    EXECUTE format(
      'CREATE POLICY %I_update ON %I FOR UPDATE TO authenticated USING (public.can_access_tenant(tenant_id)) WITH CHECK (public.can_access_tenant(tenant_id))',
      t, t
    );
  END LOOP;
END;
$$;

CREATE POLICY audit_logs_select ON audit_logs
  FOR SELECT TO authenticated
  USING (public.can_access_tenant(tenant_id) OR public.auth_is_support_user());

CREATE POLICY support_sessions_support ON support_view_sessions
  FOR ALL TO authenticated
  USING (public.auth_is_support_user())
  WITH CHECK (public.auth_is_support_user());
