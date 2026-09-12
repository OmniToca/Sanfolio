-- Přiložení papíru na blok nesmí spadnout, když chip selže.
-- Safari posílá image/jpg a HEIF — bucket je dřív odmítl.

CREATE OR REPLACE FUNCTION public.trg_recompute_bloque_status_docs()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  BEGIN
    IF NEW.bloque_id IS NOT NULL THEN
      PERFORM public.recompute_bloque_status(NEW.bloque_id);
    END IF;
    IF TG_OP = 'UPDATE'
       AND OLD.bloque_id IS NOT NULL
       AND OLD.bloque_id IS DISTINCT FROM NEW.bloque_id THEN
      PERFORM public.recompute_bloque_status(OLD.bloque_id);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Řádek dokumentu zůstane. Chip se dopočte při dalším persist.
    NULL;
  END;
  RETURN NEW;
END;
$$;

UPDATE storage.buckets
   SET allowed_mime_types = ARRAY[
     'application/pdf',
     'image/jpeg',
     'image/jpg',
     'image/pjpeg',
     'image/png',
     'image/webp',
     'image/heic',
     'image/heif'
   ]
 WHERE id = 'documentos';
