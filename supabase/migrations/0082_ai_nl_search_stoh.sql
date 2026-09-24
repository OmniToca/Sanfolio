-- AI NL: část jména (skloňování), substring NIE, adresa (bydliště + finca),
-- hromada dokladů (tipo / název / summary / body). Read-only; RLS + can_access_cliente.
-- Žádný save/send. Navazuje na 0081.

-- Soft match jednoho tokenu jména: substring, prefix, trigram, CS/ES koncovky.
CREATE OR REPLACE FUNCTION public.search_name_token_ok(p_hay TEXT, p_tok TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
SET search_path = public, extensions
AS $$
DECLARE
  hay TEXT := public.normalize_search_text(p_hay);
  tok TEXT := public.normalize_search_text(p_tok);
  w TEXT;
  stem TEXT;
BEGIN
  IF tok IS NULL OR tok = '' OR hay IS NULL OR hay = '' THEN
    RETURN false;
  END IF;
  IF char_length(tok) < 2 THEN
    RETURN false;
  END IF;
  IF strpos(hay, tok) > 0 THEN
    RETURN true;
  END IF;

  FOREACH w IN ARRAY regexp_split_to_array(hay, '\s+')
  LOOP
    IF char_length(w) < 2 THEN
      CONTINUE;
    END IF;
    IF starts_with(w, tok) OR starts_with(tok, w) THEN
      RETURN true;
    END IF;
    -- Část jména: Renat↔Renata, Susic↔Susicova (min 3–4 znaky).
    IF char_length(tok) >= 3 AND char_length(w) >= 3
       AND (starts_with(w, left(tok, greatest(3, char_length(tok) - 1)))
            OR starts_with(tok, left(w, greatest(3, char_length(w) - 1)))) THEN
      RETURN true;
    END IF;
    IF char_length(tok) >= 4 AND char_length(w) >= 4 AND w % tok THEN
      RETURN true;
    END IF;
  END LOOP;

  -- Skloňování: Renatu/Renatou → renat; Sušičovou → susicov.
  stem := regexp_replace(
    tok,
    '(ovou|ovi|ych|ami|ach|ech|ove|ovy|ova|ovu|emu|emu|oum|em|ou|um|y|u|e|a|i|e)$',
    ''
  );
  IF char_length(stem) >= 3 AND stem IS DISTINCT FROM tok AND strpos(hay, stem) > 0 THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$$;

COMMENT ON FUNCTION public.search_name_token_ok(TEXT, TEXT) IS
  'Jeden token jména: substring / prefix / trigram / CS koncovky. Pro search_name_matches.';

CREATE OR REPLACE FUNCTION public.search_name_matches(p_hay TEXT, p_q TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
SET search_path = public, extensions
AS $$
DECLARE
  hay TEXT := public.normalize_search_text(p_hay);
  q TEXT := public.normalize_search_text(p_q);
  tok TEXT;
  seen BOOLEAN := false;
BEGIN
  IF q IS NULL OR q = '' OR hay IS NULL OR hay = '' THEN
    RETURN false;
  END IF;
  IF strpos(hay, q) > 0 THEN
    RETURN true;
  END IF;
  FOREACH tok IN ARRAY regexp_split_to_array(q, '\s+')
  LOOP
    IF char_length(tok) < 2 THEN
      CONTINUE;
    END IF;
    seen := true;
    IF NOT public.search_name_token_ok(hay, tok) THEN
      RETURN false;
    END IF;
  END LOOP;
  RETURN seen;
END;
$$;

COMMENT ON FUNCTION public.search_name_matches(TEXT, TEXT) IS
  'name_hits: celý q nebo token AND (soft match per token).';

-- Stopslova + šum kolem adresy / hromady (pro jméno klienta z NL).
CREATE OR REPLACE FUNCTION public.search_query_content(p_q TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  tok TEXT;
  out_parts TEXT[] := ARRAY[]::TEXT[];
  stop TEXT[] := ARRAY[
    -- CS
    'jak','se','jsem','jsme','jste','jsou','mam','mame','máme','mate','máte',
    'nejaky','nejaka','nějaký','nějaká','nejake','nějaké','nejakeho','nějakého',
    'klient','klienta','klienti','klienty','klientu','klientů','nasi','naši','nase','naše',
    'jmenuji','jmenuje','jmenuji','jmenují','jmenovat','jmeno','jméno','jménem',
    'nie','dni','nif','cif','pas','pasport','doklad','soubor','prilozte','přiložte',
    'kolik','kde','kdo','co','pro','prosim','prosím','dekuji','děkuji',
    'dal','dál','jeho','jeji','její','jejich','neznam','neznám',
    'podle','dokumentu','dokumentů','dokumenty','dokument','doklady','dokladu',
    'hromade','hromadě','hromada','stoh','stohu','papir','papír','papiry','papíry',
    'scan','sken','skenu','email','e-mail','mail','posta','pošta','factura','faktura',
    'faktury','bydliste','bydliště','bydli','bydlí','zije','žije','adresa','adrese',
    'ulice','nemovitosti','nemovitostí','nemovitost','finca','systemu','systému',
    'system','systém','ma','má','tam','je','jsou','existuje','najdi','najdes','najdeš',
    'ukaz','ukaž','rekni','řekni','povìz','pověz','jake','jaké','jaky','jaký',
    's','a','i','u','v','z','ze','ve','na','do','od','po','za',
    -- EN
    'the','an','and','or','of','for','with','from','our','my','your','client',
    'clients','customer','customers','name','named','called','find','search','who',
    'what','how','many','have','has','is','are','do','does','we','you',
    'document','documents','pile','stack','scan','email','mail','invoice','address',
    'lives','living','street','show','list','any','some',
    -- ES
    'el','la','los','las','un','una','de','del','con','por','para','nuestro',
    'nuestra','cliente','clientes','nombre','llamado','buscar','quien','qué','que',
    'cuanto','cuántos','tenemos','tiene','hay','documento','documentos','montón',
    'monton','pila','factura','correo','dirección','direccion','domicilio','calle',
    'vivienda','finca','mostrar','dime',
    -- DE
    'der','die','das','und','oder','mit','von','für','unser','kunde','kunden',
    'namens','suchen','wer','wie','was','haben','hat','ist','sind','dokument',
    'dokumente','stapel','rechnung','adresse','strasse','straße','zeige',
    -- FR
    'le','les','des','du','au','aux','notre','nom','appeler','chercher','qui',
    'quoi','combien','avons','est','sont','document','documents','pile','facture',
    'adresse','montre','dis'
  ];
BEGIN
  IF p_q IS NULL OR btrim(p_q) = '' THEN
    RETURN '';
  END IF;
  FOREACH tok IN ARRAY regexp_split_to_array(btrim(p_q), '\s+')
  LOOP
    tok := btrim(tok, '.,;:!?„“"''()[]{}');
    IF tok = '' OR char_length(tok) < 2 THEN
      CONTINUE;
    END IF;
    IF lower(tok) = ANY (stop) THEN
      CONTINUE;
    END IF;
    out_parts := array_append(out_parts, tok);
  END LOOP;
  RETURN array_to_string(out_parts, ' ');
END;
$$;

COMMENT ON FUNCTION public.search_query_content(TEXT) IS
  'Z NL věty vyhodí stopslova (vč. hromady/adresy); zbude jméno/NIE/ulice.';

-- Aliasy NL → fragmenty tipo / text pro hromadu.
CREATE OR REPLACE FUNCTION public.search_doc_query_parts(p_q TEXT)
RETURNS TEXT[]
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  raw TEXT := lower(btrim(coalesce(p_q, '')));
  parts TEXT[] := ARRAY[]::TEXT[];
  n TEXT;
BEGIN
  IF raw = '' THEN
    RETURN parts;
  END IF;
  n := public.normalize_search_text(raw);

  IF n ~ '(dni|nie|pasport|pasaporte|passport|obcans|občans)' THEN
    parts := array_append(parts, 'dni_nie');
    parts := array_append(parts, 'pasaporte');
  END IF;
  IF n ~ '(factur|faktura|invoice|rechnung|recibo|ucten)' THEN
    parts := array_append(parts, 'factura');
    parts := array_append(parts, 'recibo');
  END IF;
  IF n ~ '(email|e-mail|mail|correo|posta|pošta|gmail|outlook)' THEN
    parts := array_append(parts, 'email');
    parts := array_append(parts, 'correo');
    parts := array_append(parts, 'mail');
  END IF;
  IF n ~ '(escritur|listin|notář|notar|deed)' THEN
    parts := array_append(parts, 'copia_escritura');
  END IF;
  IF n ~ '(poder|plna moc|plná moc|attorney)' THEN
    parts := array_append(parts, 'copia_poder');
  END IF;
  IF n ~ '(iban|bankov)' THEN
    parts := array_append(parts, 'justificante_iban');
  END IF;
  IF n ~ '(ibi|suma|catastr)' THEN
    parts := array_append(parts, 'recibo_ibi');
  END IF;
  IF n ~ '(seguro|pojist|pojišť|alarm)' THEN
    parts := array_append(parts, 'poliza_seguro');
    parts := array_append(parts, 'contrato_alarma');
  END IF;
  IF n ~ '(scan|sken|pdf|fotka|foto|papir|papír)' THEN
    parts := array_append(parts, 'scan');
  END IF;

  RETURN parts;
END;
$$;

COMMENT ON FUNCTION public.search_doc_query_parts(TEXT) IS
  'NL → tipo/text hinty pro search_cliente_documentos.';

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
#variable_conflict use_column
DECLARE
  id_q TEXT := public.normalize_id(p_q);
  name_q TEXT := btrim(coalesce(p_q, ''));
  content_q TEXT := public.search_query_content(p_q);
  id_tokens TEXT[] := public.search_query_id_tokens(p_q);
BEGIN
  IF name_q = '' THEN
    RETURN;
  END IF;
  IF content_q = '' THEN
    content_q := name_q;
  END IF;

  RETURN QUERY
  WITH id_hits AS (
    SELECT
      ci.cliente_id AS hit_id,
      CASE
        WHEN ci.value_normalized = id_q THEN 100
        WHEN id_q <> '' AND public.id_mask_match(ci.value_normalized, id_q) THEN 90
        WHEN id_q <> '' AND starts_with(ci.value_normalized, id_q) THEN 80
        WHEN id_q <> '' AND char_length(id_q) >= 3
             AND ci.value_normalized ILIKE '%' || id_q || '%' THEN 70
        WHEN id_q <> '' AND char_length(id_q) >= 3 AND ci.value_normalized % id_q THEN 60
        WHEN EXISTS (
          SELECT 1 FROM unnest(id_tokens) AS tok
          WHERE ci.value_normalized = public.normalize_id(tok)
        ) THEN 100
        WHEN EXISTS (
          SELECT 1 FROM unnest(id_tokens) AS tok
          WHERE public.id_mask_match(ci.value_normalized, public.normalize_id(tok))
        ) THEN 90
        WHEN EXISTS (
          SELECT 1 FROM unnest(id_tokens) AS tok
          WHERE starts_with(ci.value_normalized, public.normalize_id(tok))
             OR starts_with(public.normalize_id(tok), ci.value_normalized)
        ) THEN 80
        WHEN EXISTS (
          SELECT 1 FROM unnest(id_tokens) AS tok
          WHERE char_length(public.normalize_id(tok)) >= 3
            AND ci.value_normalized ILIKE '%' || public.normalize_id(tok) || '%'
        ) THEN 70
        ELSE 0
      END AS hit_score,
      CASE
        WHEN ci.value_normalized = id_q THEN 'id_exact'::TEXT
        WHEN id_q <> '' AND public.id_mask_match(ci.value_normalized, id_q) THEN 'id_mask'
        WHEN id_q <> '' AND starts_with(ci.value_normalized, id_q) THEN 'id_prefix'
        WHEN EXISTS (
          SELECT 1 FROM unnest(id_tokens) AS tok
          WHERE ci.value_normalized = public.normalize_id(tok)
             OR public.id_mask_match(ci.value_normalized, public.normalize_id(tok))
             OR starts_with(ci.value_normalized, public.normalize_id(tok))
        ) THEN 'id_token'
        WHEN id_q <> '' AND char_length(id_q) >= 3
             AND ci.value_normalized ILIKE '%' || id_q || '%' THEN 'id_substr'
        WHEN EXISTS (
          SELECT 1 FROM unnest(id_tokens) AS tok
          WHERE char_length(public.normalize_id(tok)) >= 3
            AND ci.value_normalized ILIKE '%' || public.normalize_id(tok) || '%'
        ) THEN 'id_substr'
        ELSE 'id_trgm'
      END AS hit_via
    FROM client_identifiers ci
    WHERE ci.deleted_at IS NULL
      AND public.can_access_tenant(ci.tenant_id)
      AND public.can_access_cliente(ci.cliente_id)
      AND (
        (
          id_q <> ''
          AND (
            ci.value_normalized = id_q
            OR public.id_mask_match(ci.value_normalized, id_q)
            OR starts_with(ci.value_normalized, id_q)
            OR (char_length(id_q) >= 3 AND ci.value_normalized ILIKE '%' || id_q || '%')
            OR (char_length(id_q) >= 3 AND ci.value_normalized % id_q)
          )
        )
        OR (
          cardinality(id_tokens) > 0
          AND EXISTS (
            SELECT 1 FROM unnest(id_tokens) AS tok
            WHERE ci.value_normalized = public.normalize_id(tok)
               OR public.id_mask_match(ci.value_normalized, public.normalize_id(tok))
               OR starts_with(ci.value_normalized, public.normalize_id(tok))
               OR starts_with(public.normalize_id(tok), ci.value_normalized)
               OR (
                 char_length(public.normalize_id(tok)) >= 3
                 AND ci.value_normalized ILIKE '%' || public.normalize_id(tok) || '%'
               )
          )
        )
      )
  ),
  fts_hits AS (
    SELECT
      c.id AS hit_id,
      40 AS hit_score,
      'fts'::TEXT AS hit_via
    FROM clientes c
    WHERE c.deleted_at IS NULL
      AND public.can_access_tenant(c.tenant_id)
      AND public.can_access_cliente(c.id)
      AND char_length(content_q) >= 2
      AND c.search_vector @@ plainto_tsquery('simple', content_q)
  ),
  name_hits AS (
    SELECT
      c.id AS hit_id,
      50 AS hit_score,
      'name'::TEXT AS hit_via
    FROM clientes c
    WHERE c.deleted_at IS NULL
      AND public.can_access_tenant(c.tenant_id)
      AND public.can_access_cliente(c.id)
      AND char_length(content_q) >= 2
      AND public.search_name_matches(
        concat_ws(' ', c.nombre, c.apellidos, c.email, c.tel),
        content_q
      )
  ),
  -- Bydliště karty + finca (inmuebles.direccion). Nesměšovat v UI textu, ale search smí obojí.
  address_hits AS (
    SELECT
      c.id AS hit_id,
      45 AS hit_score,
      'address'::TEXT AS hit_via
    FROM clientes c
    WHERE c.deleted_at IS NULL
      AND public.can_access_tenant(c.tenant_id)
      AND public.can_access_cliente(c.id)
      AND char_length(content_q) >= 3
      AND (
        public.search_name_matches(coalesce(c.direccion, ''), content_q)
        OR coalesce(c.direccion, '') ILIKE '%' || content_q || '%'
        OR EXISTS (
          SELECT 1
          FROM inmuebles i
          WHERE i.cliente_id = c.id
            AND i.deleted_at IS NULL
            AND (
              public.search_name_matches(coalesce(i.direccion, ''), content_q)
              OR coalesce(i.direccion, '') ILIKE '%' || content_q || '%'
            )
        )
      )
  ),
  combined AS (
    SELECT hit_id, hit_score, hit_via FROM id_hits WHERE hit_score > 0
    UNION ALL
    SELECT hit_id, hit_score, hit_via FROM fts_hits
    UNION ALL
    SELECT hit_id, hit_score, hit_via FROM name_hits
    UNION ALL
    SELECT hit_id, hit_score, hit_via FROM address_hits
  )
  SELECT
    combined.hit_id,
    max(combined.hit_score)::INT,
    (array_agg(combined.hit_via ORDER BY combined.hit_score DESC))[1]
  FROM combined
  GROUP BY combined.hit_id
  ORDER BY max(combined.hit_score) DESC
  LIMIT greatest(1, least(coalesce(p_limit, 20), 50));
END;
$$;

COMMENT ON FUNCTION public.search_clients(TEXT, INT) IS
  'NL: jméno (soft), NIE substring/token, adresa bydliště+finca. Scope: can_access_cliente.';

-- Hromada / doklady: tipo, název, summary, body. Read-only + audit.
CREATE OR REPLACE FUNCTION public.search_cliente_documentos(
  p_cliente_id UUID DEFAULT NULL,
  p_q TEXT DEFAULT NULL,
  p_limit INT DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_q TEXT := btrim(coalesce(p_q, ''));
  v_limit INT := least(greatest(coalesce(p_limit, 30), 1), 50);
  v_parts TEXT[] := public.search_doc_query_parts(v_q);
  v_content TEXT := public.search_query_content(v_q);
  v_total BIGINT;
  v_items JSONB;
  v_cliente JSONB;
  v_tenant UUID;
BEGIN
  IF p_cliente_id IS NOT NULL THEN
    IF NOT public.can_access_cliente(p_cliente_id) THEN
      RAISE EXCEPTION 'forbidden';
    END IF;
    SELECT c.tenant_id,
           jsonb_build_object(
             'id', c.id,
             'nombre', trim(both from concat_ws(' ', c.nombre, c.apellidos))
           )
      INTO v_tenant, v_cliente
      FROM clientes c
     WHERE c.id = p_cliente_id
       AND c.deleted_at IS NULL;
    IF v_tenant IS NULL THEN
      RAISE EXCEPTION 'not_found';
    END IF;
  END IF;

  WITH candidates AS (
    SELECT
      d.id,
      d.cliente_id,
      d.tipo,
      d.original_name,
      d.ai_summary,
      left(d.body_text, 800) AS body_excerpt,
      d.inmueble_id,
      d.created_at,
      c.tenant_id,
      trim(both from concat_ws(' ', c.nombre, c.apellidos)) AS cliente_nombre,
      i.direccion,
      CASE
        -- Seznam hromady u jedné karty (prázdný filtr / jen „jaké doklady“).
        WHEN p_cliente_id IS NOT NULL
             AND (v_q = '' OR (cardinality(v_parts) = 0 AND v_content = '')) THEN 10
        WHEN EXISTS (
          SELECT 1 FROM unnest(v_parts) p
          WHERE p <> '' AND coalesce(d.tipo, '') ILIKE '%' || p || '%'
        ) THEN 100
        WHEN EXISTS (
          SELECT 1 FROM unnest(v_parts) p
          WHERE p <> '' AND (
            coalesce(d.original_name, '') ILIKE '%' || p || '%'
            OR coalesce(d.ai_summary, '') ILIKE '%' || p || '%'
            OR coalesce(d.body_text, '') ILIKE '%' || p || '%'
          )
        ) THEN 80
        WHEN v_content <> '' AND (
          coalesce(d.tipo, '') ILIKE '%' || v_content || '%'
          OR coalesce(d.original_name, '') ILIKE '%' || v_content || '%'
          OR coalesce(d.ai_summary, '') ILIKE '%' || v_content || '%'
          OR coalesce(d.body_text, '') ILIKE '%' || v_content || '%'
        ) THEN 60
        WHEN v_q <> '' AND (
          coalesce(d.tipo, '') ILIKE '%' || v_q || '%'
          OR coalesce(d.original_name, '') ILIKE '%' || v_q || '%'
          OR coalesce(d.ai_summary, '') ILIKE '%' || v_q || '%'
          OR coalesce(d.body_text, '') ILIKE '%' || v_q || '%'
        ) THEN 40
        ELSE 0
      END AS hit_score
    FROM documentos d
    JOIN clientes c ON c.id = d.cliente_id AND c.deleted_at IS NULL
    LEFT JOIN inmuebles i ON i.id = d.inmueble_id AND i.deleted_at IS NULL
    WHERE d.deleted_at IS NULL
      AND public.can_access_tenant(c.tenant_id)
      AND public.can_access_cliente(d.cliente_id)
      AND (p_cliente_id IS NULL OR d.cliente_id = p_cliente_id)
      -- Office-wide jen s neprázdným q (ne dump celé kanceláře).
      AND (p_cliente_id IS NOT NULL OR v_q <> '')
  ),
  matched AS (
    SELECT *
    FROM candidates
    WHERE hit_score > 0
  )
  SELECT count(*) INTO v_total FROM matched;

  SELECT coalesce(jsonb_agg(x.obj ORDER BY x.ord DESC, x.created_at DESC), '[]'::jsonb)
    INTO v_items
    FROM (
      SELECT
        jsonb_build_object(
          'document_id', m.id,
          'cliente_id', m.cliente_id,
          'nombre', m.cliente_nombre,
          'tipo', m.tipo,
          'original_name', m.original_name,
          'ai_summary', m.ai_summary,
          'body_excerpt', m.body_excerpt,
          'inmueble_id', m.inmueble_id,
          'direccion', m.direccion,
          'score', m.hit_score,
          'albums', coalesce((
            SELECT jsonb_agg(b2.template_key ORDER BY db.created_at)
              FROM public.documento_bloques db
              JOIN public.bloques b2
                ON b2.id = db.bloque_id AND b2.deleted_at IS NULL
             WHERE db.documento_id = m.id AND db.deleted_at IS NULL
          ), '[]'::jsonb)
        ) AS obj,
        m.hit_score AS ord,
        m.created_at
      FROM matched m
      ORDER BY m.hit_score DESC, m.created_at DESC
      LIMIT v_limit
    ) x;

  IF v_tenant IS NOT NULL THEN
    INSERT INTO audit_logs (
      tenant_id, actor_id, impersonation_session_id,
      action, entity_table, entity_id, after
    ) VALUES (
      v_tenant,
      auth.uid(),
      (SELECT s.id FROM support_view_sessions s
        WHERE s.support_user_id = auth.uid()
          AND s.ended_at IS NULL
          AND s.expires_at > now()
        ORDER BY s.started_at DESC LIMIT 1),
      'ai.tool',
      'documentos',
      p_cliente_id,
      jsonb_build_object(
        'tool', 'search_cliente_documentos',
        'q', v_q,
        'total', v_total
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'total', coalesce(v_total, 0),
    'cliente', v_cliente,
    'items', coalesce(v_items, '[]'::jsonb)
  );
END;
$$;

COMMENT ON FUNCTION public.search_cliente_documentos(UUID, TEXT, INT) IS
  'Hromada: tipo/název/summary/body. List při prázdném q + cliente_id. Read-only.';

GRANT EXECUTE ON FUNCTION public.search_name_token_ok(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_name_matches(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_query_content(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_doc_query_parts(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_clients(TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_cliente_documentos(UUID, TEXT, INT) TO authenticated;
