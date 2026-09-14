# Fakturace a VeriFactu (SIF mimo jádro)

Sanfolio vystavuje a přijímá papír u klienta. **SIF (software de facturación)** — huella, QR, XML, odeslání VERI\*FACTU — žije v Edge `sif-emit` nebo v cizí app. AEAT software předem neschvaluje. Výrobce SIF podepíše **declaración responsable** (RD 1007/2023, Orden HAC/1177/2024). Povinnost: společnosti 1. 1. 2027, autónomos 1. 7. 2027. Kdo je v SII, VeriFactu nemá.

Přijaté faktury do SIF **nepatří**. To je kniha, OCR, DPH na vstupu.

Když Sanfolio čísluje, kreslí PDF a kliká Emitir, AEAT FAQ může brát Sanfolio jako **CPF** a API jako **CF třetí strany**. V DR musí být: voláme tento SIF, tato verze. Marketing „integruj a jsi v klidu“ nestačí — právník u konkrétního API.

## Rozhodnutí 13. 9. 2026: Verifacti

Napojíme [Verifacti API](https://www.verifacti.com/precios), včetně `GET /verifactu/declaracion` (DR ke stažení z programu). Pořadí a zákaz SIF v jádru: [roadmap_facturacion.md](roadmap_facturacion.md). Audit mapperu vs. docs (datum `DD-MM-YYYY`, Pendiente, klíč firmy): [audit_verifacti.md](audit_verifacti.md).

## Sandbox Emitir a Ověřit

Env na Edge (ne ve Flutteru):

| Proměnná | Význam |
| --- | --- |
| `SIF_VENDOR` | `verifacti` (jiné = `unsupported_vendor`) |
| `SIF_API_URL` | `https://api.verifacti.com` (bez lomítka na konci) |
| `SIF_API_KEY` | Bearer token / API key **firmy** (emisor) |

Bez URL a klíče `sif-emit` i `sif-status` vrátí `sif_not_configured`. Koncept zůstane v `facturas`.

Flutter posílá jen `tenant_id` + `factura_id`. Create: `fecha_expedicion` = dnešek Madrid, `fecha_operacion` = `facturas.fecha`, `Idempotency-Key` = id řádku. Po 200 je `pendiente`. Tlačítko **Ověřit** volá `sif-status` → `GET /verifactu/status`. `emitida` až AEAT přijme.

Formulář `/facturacion/nueva` ukládá obchodní řádky do `facturas.lineas`. Edge je sloučí podle sazby IVA (max 12) — to jsou Verifacti `lineas`. F1 potřebuje jméno + NIF; F2 (simplificada) smí bez příjemce, limit 3000 €.

## Due diligence (stav k rozhodnutí)

Ověřeno 13. 9. 2026 z veřejných stránek. **Vybráno Verifacti** — viz roadmap. Ceny a DR se mění — před produkcí znovu.

### Verifacti ([verifacti.com](https://www.verifacti.com/)) — zvolené API

- REST `POST /verifactu/create`, stav `GET /verifactu/status`, DR `GET /verifactu/declaracion`.
- **Colaborador social** AEAT (Bilbabit SL, convenio 017). Certifikát FNMT kanceláře do appky nestrkáte; v produkci **modelo de representación**.
- TicketBAI: samostatná API, jedna integrace navíc.
- Cena (veřejná): od **2,90 € / NIF / měsíc**; účet zdarma na test; platba až produkční AEAT. Limit cca 3000 faktur / NIF / měsíc, nad to 2 € / 1000.
- Mixed architecture: DR má Verifacti **i** software, který volá API (Sanfolio / OmniToca). Oni dávají šablonu.

### verifactuapi.es ([verifactuapi.es](https://verifactuapi.es/))

- REST `POST /api/alta-registro-facturacion`, login Bearer, webhooky, QR v odpovědi.
- Tvrdí colaborador social + TicketBAI (Álava, Gipuzkoa, Bizkaia, Navarra) v jedné API.
- Sandbox AEAT zdarma; **produkční ceník jen na poptávku**.
- Testovací CIF emisoru: `A39200019`.

### Asesorio (záloha)

- REST + sandbox. Tvrdí, že **oni** jsou SIF a podepisují svou DR.
- Starter od 29 €/měsíc (3000 callů) + 5 €/NIF emisor; Free bez produkčního Registra.

INFOAL / efsta EFR v kódu nemáme — stejný adapter, jiný `SIF_VENDOR`, až bude smlouva.

Vlastní SIF-app (`facturas.omnitoca`) dává smysl, až OmniToca fakturuje ve velkém a nechcete marži Verifacti. Do 2027 to není první tah Sanfolia. Do `carpeta` a DocuDocu klonu VeriFactu nepatří.
