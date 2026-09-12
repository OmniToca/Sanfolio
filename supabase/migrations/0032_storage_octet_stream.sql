-- Safari / pošta pošle PDF jako octet-stream. Bucket je privátní, cesta = tenant.
-- Bez této položky Storage nahrání tiše odmítne a gestor vidí jen uploadError.

UPDATE storage.buckets
   SET allowed_mime_types = ARRAY[
     'application/pdf',
     'application/octet-stream',
     'binary/octet-stream',
     'image/jpeg',
     'image/jpg',
     'image/pjpeg',
     'image/png',
     'image/webp',
     'image/heic',
     'image/heif'
   ]
 WHERE id = 'documentos';
