-- Rozsah týmu na zbylé desce: zápis, inbox, kampaně, AI, pošta, storage.
-- 0070 schovalo SELECT karet a bloků. Tady totéž u lhůt, pošty a office RPC.

CREATE OR REPLACE FUNCTION public.staff_may_create_clientes(_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.can_access_tenant(_tenant_id)
    AND NOT public.staff_is_scoped(_tenant_id);
$$;

CREATE OR REPLACE FUNCTION public.can_access_bloque(_bloque_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.bloques b
      JOIN public.expedientes e ON e.id = b.expediente_id
     WHERE b.id = _bloque_id
       AND public.can_access_cliente(e.cliente_id)
       AND public.can_use_bloque_template(e.cliente_id, b.template_key)
  );
$$;

-- Řádek bez klienta: owner a nescopovaný. Scoped jen přiřazená karta.
CREATE OR REPLACE FUNCTION public.staff_row_cliente_ok(
  _tenant_id UUID,
  _cliente_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.can_access_tenant(_tenant_id)
    AND CASE
      WHEN _cliente_id IS NULL THEN NOT public.staff_is_scoped(_tenant_id)
      ELSE public.can_access_cliente(_cliente_id)
    END;
$$;

GRANT EXECUTE ON FUNCTION public.staff_may_create_clientes(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_bloque(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_row_cliente_ok(UUID, UUID) TO authenticated;

COMMENT ON FUNCTION public.staff_may_create_clientes(UUID) IS
  'Novou kartu zakládá owner a nescopovaný člen. Scoped jen přiřazené.';
COMMENT ON FUNCTION public.can_access_bloque(UUID) IS
  'Blok desky v rozsahu člena (identita vždy, jinak ticked služby).';

DROP POLICY IF EXISTS clientes_insert ON public.clientes;
CREATE POLICY clientes_insert ON public.clientes
  FOR INSERT TO authenticated
  WITH CHECK (public.staff_may_create_clientes(tenant_id));

DROP POLICY IF EXISTS clientes_update ON public.clientes;
CREATE POLICY clientes_update ON public.clientes
  FOR UPDATE TO authenticated
  USING (public.can_access_cliente(id))
  WITH CHECK (public.can_access_cliente(id));

DROP POLICY IF EXISTS documentos_insert ON public.documentos;
CREATE POLICY documentos_insert ON public.documentos
  FOR INSERT TO authenticated
  WITH CHECK (public.staff_row_cliente_ok(tenant_id, cliente_id));

DROP POLICY IF EXISTS documentos_update ON public.documentos;
CREATE POLICY documentos_update ON public.documentos
  FOR UPDATE TO authenticated
  USING (public.staff_row_cliente_ok(tenant_id, cliente_id))
  WITH CHECK (public.staff_row_cliente_ok(tenant_id, cliente_id));

DROP POLICY IF EXISTS expedientes_insert ON public.expedientes;
CREATE POLICY expedientes_insert ON public.expedientes
  FOR INSERT TO authenticated
  WITH CHECK (
    public.can_access_tenant(tenant_id)
    AND public.can_access_cliente(cliente_id)
  );

DROP POLICY IF EXISTS expedientes_update ON public.expedientes;
CREATE POLICY expedientes_update ON public.expedientes
  FOR UPDATE TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND public.can_access_cliente(cliente_id)
  )
  WITH CHECK (
    public.can_access_tenant(tenant_id)
    AND public.can_access_cliente(cliente_id)
    AND (
      deleted_at IS NULL
      OR public.can_soft_delete_expediente(tenant_id)
    )
  );

DROP POLICY IF EXISTS bloques_insert ON public.bloques;
CREATE POLICY bloques_insert ON public.bloques
  FOR INSERT TO authenticated
  WITH CHECK (
    public.can_access_tenant(tenant_id)
    AND EXISTS (
      SELECT 1
        FROM public.expedientes e
       WHERE e.id = expediente_id
         AND public.can_access_cliente(e.cliente_id)
         AND public.can_use_bloque_template(e.cliente_id, template_key)
    )
  );

DROP POLICY IF EXISTS bloques_update ON public.bloques;
CREATE POLICY bloques_update ON public.bloques
  FOR UPDATE TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND EXISTS (
      SELECT 1
        FROM public.expedientes e
       WHERE e.id = expediente_id
         AND public.can_access_cliente(e.cliente_id)
         AND public.can_use_bloque_template(e.cliente_id, template_key)
    )
  )
  WITH CHECK (
    public.can_access_tenant(tenant_id)
    AND EXISTS (
      SELECT 1
        FROM public.expedientes e
       WHERE e.id = expediente_id
         AND public.can_access_cliente(e.cliente_id)
         AND public.can_use_bloque_template(e.cliente_id, template_key)
    )
  );

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'client_identifiers',
    'inmuebles',
    'mensajes',
    'client_contacts',
    'documento_chunks'
  ]
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I_select ON public.%I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_insert ON public.%I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_update ON public.%I', t, t);
    EXECUTE format(
      'CREATE POLICY %I_select ON public.%I FOR SELECT TO authenticated USING (public.can_access_tenant(tenant_id) AND public.can_access_cliente(cliente_id))',
      t, t
    );
    EXECUTE format(
      'CREATE POLICY %I_insert ON public.%I FOR INSERT TO authenticated WITH CHECK (public.can_access_tenant(tenant_id) AND public.can_access_cliente(cliente_id))',
      t, t
    );
    EXECUTE format(
      'CREATE POLICY %I_update ON public.%I FOR UPDATE TO authenticated USING (public.can_access_tenant(tenant_id) AND public.can_access_cliente(cliente_id)) WITH CHECK (public.can_access_tenant(tenant_id) AND public.can_access_cliente(cliente_id))',
      t, t
    );
  END LOOP;
END;
$$;

DROP POLICY IF EXISTS plazos_select ON public.plazos;
DROP POLICY IF EXISTS plazos_insert ON public.plazos;
DROP POLICY IF EXISTS plazos_update ON public.plazos;
CREATE POLICY plazos_select ON public.plazos
  FOR SELECT TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND (
      (
        bloque_id IS NOT NULL
        AND public.can_access_bloque(bloque_id)
      )
      OR (
        bloque_id IS NULL
        AND expediente_id IS NOT NULL
        AND public.can_access_cliente((
          SELECT e.cliente_id FROM public.expedientes e WHERE e.id = expediente_id
        ))
      )
    )
  );
CREATE POLICY plazos_insert ON public.plazos
  FOR INSERT TO authenticated
  WITH CHECK (
    public.can_access_tenant(tenant_id)
    AND (
      (
        bloque_id IS NOT NULL
        AND public.can_access_bloque(bloque_id)
      )
      OR (
        bloque_id IS NULL
        AND expediente_id IS NOT NULL
        AND public.can_access_cliente((
          SELECT e.cliente_id FROM public.expedientes e WHERE e.id = expediente_id
        ))
      )
    )
  );
CREATE POLICY plazos_update ON public.plazos
  FOR UPDATE TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND (
      (
        bloque_id IS NOT NULL
        AND public.can_access_bloque(bloque_id)
      )
      OR (
        bloque_id IS NULL
        AND expediente_id IS NOT NULL
        AND public.can_access_cliente((
          SELECT e.cliente_id FROM public.expedientes e WHERE e.id = expediente_id
        ))
      )
    )
  )
  WITH CHECK (
    public.can_access_tenant(tenant_id)
    AND (
      (
        bloque_id IS NOT NULL
        AND public.can_access_bloque(bloque_id)
      )
      OR (
        bloque_id IS NULL
        AND expediente_id IS NOT NULL
        AND public.can_access_cliente((
          SELECT e.cliente_id FROM public.expedientes e WHERE e.id = expediente_id
        ))
      )
    )
  );

DROP POLICY IF EXISTS provision_movements_select ON public.provision_movements;
DROP POLICY IF EXISTS provision_movements_insert ON public.provision_movements;
DROP POLICY IF EXISTS provision_movements_update ON public.provision_movements;
CREATE POLICY provision_movements_select ON public.provision_movements
  FOR SELECT TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND public.can_access_cliente((
      SELECT e.cliente_id FROM public.expedientes e WHERE e.id = expediente_id
    ))
  );
CREATE POLICY provision_movements_insert ON public.provision_movements
  FOR INSERT TO authenticated
  WITH CHECK (
    public.can_access_tenant(tenant_id)
    AND public.can_access_cliente((
      SELECT e.cliente_id FROM public.expedientes e WHERE e.id = expediente_id
    ))
  );
CREATE POLICY provision_movements_update ON public.provision_movements
  FOR UPDATE TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND public.can_access_cliente((
      SELECT e.cliente_id FROM public.expedientes e WHERE e.id = expediente_id
    ))
  )
  WITH CHECK (
    public.can_access_tenant(tenant_id)
    AND public.can_access_cliente((
      SELECT e.cliente_id FROM public.expedientes e WHERE e.id = expediente_id
    ))
  );

DROP POLICY IF EXISTS plazo_reminders_select ON public.plazo_reminders;
CREATE POLICY plazo_reminders_select ON public.plazo_reminders
  FOR SELECT TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND EXISTS (
      SELECT 1 FROM public.plazos p WHERE p.id = plazo_id
    )
  );

DROP POLICY IF EXISTS inmueble_titulares_select ON public.inmueble_titulares;
DROP POLICY IF EXISTS inmueble_titulares_insert ON public.inmueble_titulares;
DROP POLICY IF EXISTS inmueble_titulares_update ON public.inmueble_titulares;
CREATE POLICY inmueble_titulares_select ON public.inmueble_titulares
  FOR SELECT TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND (
      EXISTS (
        SELECT 1 FROM public.inmuebles i
         WHERE i.id = inmueble_id
           AND public.can_access_cliente(i.cliente_id)
      )
      OR (
        cliente_id IS NOT NULL
        AND public.can_access_cliente(cliente_id)
      )
    )
  );
CREATE POLICY inmueble_titulares_insert ON public.inmueble_titulares
  FOR INSERT TO authenticated
  WITH CHECK (
    public.can_access_tenant(tenant_id)
    AND (
      EXISTS (
        SELECT 1 FROM public.inmuebles i
         WHERE i.id = inmueble_id
           AND public.can_access_cliente(i.cliente_id)
      )
      OR (
        cliente_id IS NOT NULL
        AND public.can_access_cliente(cliente_id)
      )
    )
  );
CREATE POLICY inmueble_titulares_update ON public.inmueble_titulares
  FOR UPDATE TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND (
      EXISTS (
        SELECT 1 FROM public.inmuebles i
         WHERE i.id = inmueble_id
           AND public.can_access_cliente(i.cliente_id)
      )
      OR (
        cliente_id IS NOT NULL
        AND public.can_access_cliente(cliente_id)
      )
    )
  )
  WITH CHECK (
    public.can_access_tenant(tenant_id)
    AND (
      EXISTS (
        SELECT 1 FROM public.inmuebles i
         WHERE i.id = inmueble_id
           AND public.can_access_cliente(i.cliente_id)
      )
      OR (
        cliente_id IS NOT NULL
        AND public.can_access_cliente(cliente_id)
      )
    )
  );

DROP POLICY IF EXISTS documento_bloques_select ON public.documento_bloques;
DROP POLICY IF EXISTS documento_bloques_insert ON public.documento_bloques;
DROP POLICY IF EXISTS documento_bloques_update ON public.documento_bloques;
CREATE POLICY documento_bloques_select ON public.documento_bloques
  FOR SELECT TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND public.can_access_bloque(bloque_id)
    AND EXISTS (
      SELECT 1 FROM public.documentos d
       WHERE d.id = documento_id
         AND public.staff_row_cliente_ok(d.tenant_id, d.cliente_id)
    )
  );
CREATE POLICY documento_bloques_insert ON public.documento_bloques
  FOR INSERT TO authenticated
  WITH CHECK (
    public.can_access_tenant(tenant_id)
    AND public.can_access_bloque(bloque_id)
    AND EXISTS (
      SELECT 1 FROM public.documentos d
       WHERE d.id = documento_id
         AND public.staff_row_cliente_ok(d.tenant_id, d.cliente_id)
    )
  );
CREATE POLICY documento_bloques_update ON public.documento_bloques
  FOR UPDATE TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND public.can_access_bloque(bloque_id)
  )
  WITH CHECK (
    public.can_access_tenant(tenant_id)
    AND public.can_access_bloque(bloque_id)
  );

DROP POLICY IF EXISTS ai_drafts_select ON public.ai_drafts;
DROP POLICY IF EXISTS ai_drafts_insert ON public.ai_drafts;
DROP POLICY IF EXISTS ai_drafts_update ON public.ai_drafts;
CREATE POLICY ai_drafts_select ON public.ai_drafts
  FOR SELECT TO authenticated
  USING (public.staff_row_cliente_ok(tenant_id, cliente_id));
CREATE POLICY ai_drafts_insert ON public.ai_drafts
  FOR INSERT TO authenticated
  WITH CHECK (public.staff_row_cliente_ok(tenant_id, cliente_id));
CREATE POLICY ai_drafts_update ON public.ai_drafts
  FOR UPDATE TO authenticated
  USING (public.staff_row_cliente_ok(tenant_id, cliente_id))
  WITH CHECK (public.staff_row_cliente_ok(tenant_id, cliente_id));

DROP POLICY IF EXISTS ai_conversations_select ON public.ai_conversations;
DROP POLICY IF EXISTS ai_conversations_insert ON public.ai_conversations;
DROP POLICY IF EXISTS ai_conversations_update ON public.ai_conversations;
CREATE POLICY ai_conversations_select ON public.ai_conversations
  FOR SELECT TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND (
      NOT public.staff_is_scoped(tenant_id)
      OR created_by IS NOT DISTINCT FROM auth.uid()
    )
  );
CREATE POLICY ai_conversations_insert ON public.ai_conversations
  FOR INSERT TO authenticated
  WITH CHECK (
    public.can_access_tenant(tenant_id)
    AND (
      NOT public.staff_is_scoped(tenant_id)
      OR created_by IS NOT DISTINCT FROM auth.uid()
    )
  );
CREATE POLICY ai_conversations_update ON public.ai_conversations
  FOR UPDATE TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND (
      NOT public.staff_is_scoped(tenant_id)
      OR created_by IS NOT DISTINCT FROM auth.uid()
    )
  )
  WITH CHECK (
    public.can_access_tenant(tenant_id)
    AND (
      NOT public.staff_is_scoped(tenant_id)
      OR created_by IS NOT DISTINCT FROM auth.uid()
    )
  );

DROP POLICY IF EXISTS ai_messages_select ON public.ai_messages;
CREATE POLICY ai_messages_select ON public.ai_messages
  FOR SELECT TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND EXISTS (
      SELECT 1 FROM public.ai_conversations c WHERE c.id = conversation_id
    )
  );

DROP POLICY IF EXISTS facturas_select ON public.facturas;
DROP POLICY IF EXISTS facturas_insert ON public.facturas;
DROP POLICY IF EXISTS facturas_update ON public.facturas;
CREATE POLICY facturas_select ON public.facturas
  FOR SELECT TO authenticated
  USING (public.staff_row_cliente_ok(tenant_id, cliente_id));
CREATE POLICY facturas_insert ON public.facturas
  FOR INSERT TO authenticated
  WITH CHECK (public.staff_row_cliente_ok(tenant_id, cliente_id));
CREATE POLICY facturas_update ON public.facturas
  FOR UPDATE TO authenticated
  USING (public.staff_row_cliente_ok(tenant_id, cliente_id))
  WITH CHECK (public.staff_row_cliente_ok(tenant_id, cliente_id));

DROP POLICY IF EXISTS legal_holds_select ON public.legal_holds;
CREATE POLICY legal_holds_select ON public.legal_holds
  FOR SELECT TO authenticated
  USING (
    public.staff_row_cliente_ok(tenant_id, cliente_id)
    OR (
      documento_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.documentos d
         WHERE d.id = documento_id
           AND public.staff_row_cliente_ok(d.tenant_id, d.cliente_id)
      )
    )
  );

DROP POLICY IF EXISTS posta_messages_select ON public.posta_messages;
CREATE POLICY posta_messages_select ON public.posta_messages
  FOR SELECT TO authenticated
  USING (public.staff_row_cliente_ok(tenant_id, cliente_id));

DROP POLICY IF EXISTS posta_attachments_select ON public.posta_attachments;
CREATE POLICY posta_attachments_select ON public.posta_attachments
  FOR SELECT TO authenticated
  USING (
    public.can_access_tenant(tenant_id)
    AND EXISTS (
      SELECT 1 FROM public.posta_messages m WHERE m.id = message_id
    )
  );

CREATE OR REPLACE FUNCTION public.storage_cliente_id(object_name TEXT)
RETURNS UUID
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  folder TEXT := (storage.foldername(object_name))[2];
BEGIN
  IF folder IS NULL
     OR folder !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    RETURN NULL;
  END IF;
  RETURN folder::uuid;
END;
$$;

COMMENT ON FUNCTION public.storage_cliente_id IS
  'Druhá složka cesty ve Storage = cliente_id. Jinak NULL → RLS odmítne.';

DROP POLICY IF EXISTS documentos_storage_select ON storage.objects;
CREATE POLICY documentos_storage_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documentos'
    AND public.can_access_tenant(public.storage_tenant_id(name))
    AND public.storage_cliente_id(name) IS NOT NULL
    AND public.can_access_cliente(public.storage_cliente_id(name))
  );

DROP POLICY IF EXISTS documentos_storage_insert ON storage.objects;
CREATE POLICY documentos_storage_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'documentos'
    AND public.can_access_tenant(public.storage_tenant_id(name))
    AND public.storage_cliente_id(name) IS NOT NULL
    AND public.can_access_cliente(public.storage_cliente_id(name))
  );

DROP POLICY IF EXISTS documentos_storage_update ON storage.objects;
CREATE POLICY documentos_storage_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'documentos'
    AND public.can_access_tenant(public.storage_tenant_id(name))
    AND public.storage_cliente_id(name) IS NOT NULL
    AND public.can_access_cliente(public.storage_cliente_id(name))
  )
  WITH CHECK (
    bucket_id = 'documentos'
    AND public.can_access_tenant(public.storage_tenant_id(name))
    AND public.storage_cliente_id(name) IS NOT NULL
    AND public.can_access_cliente(public.storage_cliente_id(name))
  );

-- Office RPC dřív DEFINER = celá kancelář. INVOKER čte už oříznuté RLS.
ALTER FUNCTION public.pending_extract_queue(UUID) SECURITY INVOKER;
ALTER FUNCTION public.pending_extract_count(UUID) SECURITY INVOKER;
ALTER FUNCTION public.provision_owing(UUID) SECURITY INVOKER;
ALTER FUNCTION public.provision_owing_count(UUID) SECURITY INVOKER;
ALTER FUNCTION public.office_citas(UUID, DATE) SECURITY INVOKER;
ALTER FUNCTION public.office_citas_count(UUID, DATE) SECURITY INVOKER;
ALTER FUNCTION public.expiring_items(UUID) SECURITY INVOKER;
ALTER FUNCTION public.expiring_items_count(UUID) SECURITY INVOKER;
ALTER FUNCTION public.season_210(UUID) SECURITY INVOKER;
ALTER FUNCTION public.season_210_count(UUID) SECURITY INVOKER;
ALTER FUNCTION public.season_ibi(UUID) SECURITY INVOKER;
ALTER FUNCTION public.season_ibi_count(UUID) SECURITY INVOKER;
ALTER FUNCTION public.overpaying_suministro(UUID) SECURITY INVOKER;
ALTER FUNCTION public.overpaying_suministro_count(UUID) SECURITY INVOKER;
ALTER FUNCTION public.reach_gaps(UUID) SECURITY INVOKER;
ALTER FUNCTION public.reach_gaps_count(UUID) SECURITY INVOKER;
ALTER FUNCTION public.search_document_text(UUID, TEXT, INT) SECURITY INVOKER;
ALTER FUNCTION public.search_document_chunks(UUID, JSONB, INT) SECURITY INVOKER;
ALTER FUNCTION public.query_suministro(UUID, TEXT, TEXT, INT) SECURITY INVOKER;
ALTER FUNCTION public.query_plazos_office(UUID, TEXT, INT, INT) SECURITY INVOKER;
ALTER FUNCTION public.query_escritura(UUID, TEXT, INT) SECURITY INVOKER;
ALTER FUNCTION public.ai_get_cliente(UUID) SECURITY INVOKER;
ALTER FUNCTION public.cliente_poder_glance(UUID, UUID[]) SECURITY INVOKER;
ALTER FUNCTION public.after_notary(UUID) SECURITY INVOKER;
ALTER FUNCTION public.after_notary_count(UUID) SECURITY INVOKER;
