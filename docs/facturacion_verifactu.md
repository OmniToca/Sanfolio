# Fakturace a VeriFactu (SIF mimo jádro)

Sanfolio vystavuje a přijímá papír u klienta. **SIF (software de facturación)** — huella, QR, XML, odeslání VERI\*FACTU — žije v Edge `sif-emit` nebo v cizí app. AEAT software předem neschvaluje. Výrobce SIF podepíše **declaración responsable** (RD 1007/2023, Orden HAC/1177/2024). Povinnost: společnosti 1. 1. 2027, autónomos 1. 7. 2027. Kdo je v SII, VeriFactu nemá.

Přijaté faktury do SIF **nepatří**. To je kniha, OCR, DPH na vstupu.

Když Sanfolio čísluje, kreslí PDF a kliká Emitir, AEAT FAQ může brát Sanfolio jako **CPF** a API jako **CF třetí strany**. V DR musí být: voláme tento SIF, tato verze. Marketing „integruj a jsi v klidu“ nestačí — právník u konkrétního API.

## Sandbox Emitir

Env na Edge (ne ve Flutteru):

| Proměnná | Význam |
| --- | --- |
| `SIF_VENDOR` | `verifacti` (default) nebo `verifactuapi` |
| `SIF_API_URL` | base URL bez lomítka na konci |
| `SIF_API_KEY` | Bearer token / API key emisoru |

Bez URL a klíče funkce vrátí `sif_not_configured`. Koncept zůstane v `facturas`. Testovací NIF u AEAT sandboxu (verifactuapi.es): emisor `A39200019`.

Flutter posílá jen `tenant_id` + `factura_id`. Payload skládá Edge z `facturas` + `tenant_settings.emisor_nif`.

## Due diligence (ne nákup)

Ověřeno 13. 9. 2026 z veřejných stránek. Ceny a DR se mění — před produkcí znovu.

### Verifacti ([verifacti.com](https://www.verifacti.com/))

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
