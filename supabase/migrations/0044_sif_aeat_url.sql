-- Odkaz AEAT na ověření QR (pole `url` z Verifacti create). PNG zůstává v sif_qr_url.

ALTER TABLE facturas
  ADD COLUMN IF NOT EXISTS sif_aeat_url TEXT;

COMMENT ON COLUMN facturas.sif_aeat_url IS
  'HTTPS odkaz AEAT ValidarQR z odpovědi create. Flutter jen otevře, nekreslí QR.';
