-- AI / search: volná věta („máme klienta Renata“, „NIE Y9908856X“) musí
-- najít kartu. 0080 opravilo jméno bez normalize_id, ale celé NL sotva
-- projde token AND a normalize_id věty slepí NIE do jednoho řetězce.

-- Stopslova CS/ES/EN/DE/FR + kancelářský šum. Token ≥ 2 mimo seznam = jméno/NIE.
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
    'podle','dokumentu','dokumentů','hromade','hromadě',
    'nemovitosti','nemovitostí','nemovitost','systemu','systému','system','systém',
    's','a','i','u','v','z','ze','ve','na','do','od','po','za',
    -- EN
    'the','an','and','or','of','for','with','from','our','my','your','client',
    'clients','customer','customers','name','named','called','find','search','who',
    'what','how','many','have','has','is','are','do','does','we','you',
    -- ES
    'el','la','los','las','un','una','de','del','con','por','para','nuestro',
    'nuestra','cliente','clientes','nombre','llamado','buscar','quien','qué','que',
    'cuanto','cuántos','tenemos','tiene','hay',
    -- DE
    'der','die','das','und','oder','mit','von','für','unser','kunde','kunden',
    'namens','suchen','wer','wie','was','haben','hat','ist','sind',
    -- FR
    'le','les','des','du','au','aux','notre','nom','appeler','chercher','qui',
    'quoi','combien','avons','est','sont'
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
  'Z NL věty vyhodí stopslova; zbude jméno/NIE pro search_clients.';

-- NIE/DNI tokeny uvnitř věty (ne celý normalize_id věty).
CREATE OR REPLACE FUNCTION public.search_query_id_tokens(p_q TEXT)
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT coalesce(array_agg(DISTINCT upper(x.tok)), ARRAY[]::TEXT[])
  FROM (
    SELECT regexp_replace(t.tok, '[^A-Za-z0-9*]', '', 'g') AS tok
    FROM regexp_split_to_table(coalesce(p_q, ''), '[^A-Za-z0-9*]+') AS t(tok)
  ) x
  WHERE char_length(x.tok) >= 4
    AND (
      x.tok ~* '^[XYZ][0-9*]{5,8}[A-Z0-9*]?$'
      OR x.tok ~* '^[0-9*]{7,9}[A-Z]?$'
      OR x.tok ~* '^[XYZ][0-9*]{3,}$'
      OR x.tok ~* '^[0-9*]{5,}$'
    );
$$;

COMMENT ON FUNCTION public.search_query_id_tokens(TEXT) IS
  'NIE/DNI úlomky z volné věty pro id_hits.';

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
  -- Když věta měla jen stopslova, zkus aspoň původní q (kratší jména).
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
  combined AS (
    SELECT hit_id, hit_score, hit_via FROM id_hits WHERE hit_score > 0
    UNION ALL
    SELECT hit_id, hit_score, hit_via FROM fts_hits
    UNION ALL
    SELECT hit_id, hit_score, hit_via FROM name_hits
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
  'NIE z tokenů ve větě + jméno po stopslovech (token AND + fold). Scope: can_access_cliente.';

GRANT EXECUTE ON FUNCTION public.search_query_content(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_query_id_tokens(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_clients(TEXT, INT) TO authenticated;
