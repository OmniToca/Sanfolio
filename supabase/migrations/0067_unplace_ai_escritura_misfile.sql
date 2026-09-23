-- AI strčila poder/fakturu do alba escritura (notario v těle PDF).
-- Lidské album se neschovává. Papír se vrátí na hromadu.

WITH gone AS (
  UPDATE public.documento_bloques db
     SET deleted_at = now()
   WHERE db.deleted_at IS NULL
     AND db.source = 'ai'
     AND db.id IN (
       SELECT db2.id
         FROM public.documento_bloques db2
         JOIN public.documentos d
           ON d.id = db2.documento_id
          AND d.deleted_at IS NULL
         JOIN public.bloques b
           ON b.id = db2.bloque_id
          AND b.deleted_at IS NULL
        WHERE db2.deleted_at IS NULL
          AND db2.source = 'ai'
          AND b.template_key = 'escritura'
          AND (
            d.original_name ~* 'p[oó]der|apoderad'
            OR d.original_name ~* 'factura|invoice|recibo'
          )
          AND NOT EXISTS (
            SELECT 1
              FROM public.documento_bloques h
             WHERE h.documento_id = d.id
               AND h.deleted_at IS NULL
               AND h.source = 'human'
          )
     )
  RETURNING db.documento_id
)
SELECT public.sync_documento_primary_bloque(documento_id)
  FROM gone;
