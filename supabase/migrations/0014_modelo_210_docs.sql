-- Checklist papírů modelo 210. Žádný daňový výpočet.

UPDATE bloque_templates
SET required_doc_types = '{escritura_o_nota_simple,recibo_ibi,certificado_catastral}'
WHERE key = 'modelo_210';
