-- RETURNS TABLE má sloupec `score`. V plpgsql je to zároveň proměnná, takže
-- `WHERE score > 0` spadne (42702 ambiguous). Jakýkoli znak v hledání shodil
-- seznam klientů. Vnitřní aliasy jsou hit_*, výstup zůstává cliente_id/score.

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
  q TEXT := public.normalize_id(p_q);
BEGIN
  IF q IS NULL OR btrim(q) = '' THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH id_hits AS (
    SELECT
      ci.cliente_id AS hit_id,
      CASE
        WHEN ci.value_normalized = q THEN 100
        WHEN public.id_mask_match(ci.value_normalized, q) THEN 90
        WHEN starts_with(ci.value_normalized, q) THEN 80
        WHEN char_length(q) >= 3 AND ci.value_normalized % q THEN 60
        ELSE 0
      END AS hit_score,
      CASE
        WHEN ci.value_normalized = q THEN 'id_exact'::TEXT
        WHEN public.id_mask_match(ci.value_normalized, q) THEN 'id_mask'
        WHEN starts_with(ci.value_normalized, q) THEN 'id_prefix'
        ELSE 'id_trgm'
      END AS hit_via
    FROM client_identifiers ci
    WHERE ci.deleted_at IS NULL
      AND public.can_access_tenant(ci.tenant_id)
      AND (
        ci.value_normalized = q
        OR public.id_mask_match(ci.value_normalized, q)
        OR starts_with(ci.value_normalized, q)
        OR (char_length(q) >= 3 AND ci.value_normalized % q)
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
      AND char_length(btrim(coalesce(p_q, ''))) >= 2
      AND c.search_vector @@ plainto_tsquery('simple', coalesce(p_q, ''))
  ),
  name_hits AS (
    SELECT
      c.id AS hit_id,
      50 AS hit_score,
      'name'::TEXT AS hit_via
    FROM clientes c
    WHERE c.deleted_at IS NULL
      AND public.can_access_tenant(c.tenant_id)
      AND (
        strpos(upper(coalesce(c.nombre, '')), q) > 0
        OR strpos(upper(coalesce(c.apellidos, '')), q) > 0
        OR strpos(upper(coalesce(c.tel, '')), q) > 0
        OR strpos(upper(coalesce(c.email, '')), q) > 0
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

GRANT EXECUTE ON FUNCTION public.search_clients(TEXT, INT) TO authenticated;

COMMENT ON FUNCTION public.search_clients(TEXT, INT) IS
  'NIE maska / prefix / FTS. Výstup score; uvnitř hit_score kvůli plpgsql 42702.';
