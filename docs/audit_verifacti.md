# Audit Verifacti API (13. 9. 2026)

Zdroj: [verifacti.com/docs](https://www.verifacti.com/docs), [příklady](https://www.verifacti.com/docs/ejemplos), [ceník / OpenAPI](https://www.verifacti.com/precios). Smlouva nasazení: [roadmap_facturacion.md](roadmap_facturacion.md). Architektura knihy: [facturacion_verifactu.md](facturacion_verifactu.md).

**Verdikt:** Verifacti je správný SIF mimo jádro. `sif-emit` má správný směr (Flutter posílá jen `tenant_id` + `factura_id`), ale **nesmí se zapnout živý klíč**, dokud Edge nepošle datum `DD-MM-YYYY`, `Idempotency-Key` a nenechá fakturu v `pendiente`, dokud AEAT nepřijme záznam. Jeden globální `SIF_API_KEY` stačí jen dokud emituje jedna kancelář.

Přijaté faktury do tohoto API **nepatří**. Hash / QR / XML v Flutteru **ne**.

---

## Co Verifacti je

REST na `https://api.verifacti.com`. Bearer `Authorization: API_KEY`. **Klíč firmy (emisor)** skládá huellu, QR, XML a frontu AEAT. NIF emisoru v JSON **není** — určuje ho klíč. Účetní klíč (jiný) je na správu NIF (`POST /nifs`) a modelo de representación.

Testovací empresa je v bezplatném účtu (AEAT test). Produkční NIF = platba + modelo de representación. Colaborador social: Bilbabit SL, convenio 017. Cena od ~2,90 € / NIF / měsíc; ~3000 faktur / NIF / měsíc, nad to 2 € / 1000.

Veřejná dokumentace **nedokumentuje webhooky**. Stav po `create` je `Pendiente` (odeslání AEAT až ~2 min). První cesta = poll `GET /verifactu/status` podle `uuid`. Webhook až když ho Verifacti potvrdí písemně.

---

## Endpointy — co bereme

| Endpoint | V1 Sanfolio | Proč |
| --- | --- | --- |
| `GET /verifactu/health` | ano, před prvním Emitir | ověří, že klíč žije |
| `POST /verifactu/create` | ano | Emitir |
| `GET /verifactu/status` | ano | uuid z create; Flutter jen ukáže |
| `GET /verifactu/declaracion` | ano | DR ke stažení ze Settings |
| `POST /verifactu/cancel` | hned po sandboxu | storno, ne tichý edit |
| `POST /verifactu/status` | záloha | série + číslo + datum, když uuid chybí |
| `PUT /verifactu/modify` | později | subsanar, ne první tah |
| `POST /verifactu/create_bulk` | ne | max 50; kniha je po jedné |
| `POST /verifactu/list` / `export` / `downloadXML` | později | XML drží oni; my ukládáme uuid + stav |
| TicketBAI API | mimo plán | jiná integrace |

Create vrací `uuid` + QR jako **base64** (ne URL). `fecha_expedicion` **musí být dnešek** (Europe/Madrid). `fecha_operacion` smí být dřív. Datum v příkladech: **`DD-MM-YYYY`**. `lineas` max **12**. `serie`+`numero` ≤ 60 znaků. F1 vyžaduje `nif` + `nombre` příjemce; u fyzické osoby musí jméno sedět s DNI/NIE (censo AEAT, default `validar_destinatario`). F2 (zjednodušená) bez příjemce, limit 3000 €.

`POST /verifactu/create` vrací **409**, když stejná `Idempotency-Key` ještě běží, **422** když se stejný klíč pošle s jiným tělem. Klíč = `facturas.id`.

---

## Mezery v `sif-emit` (kód 14. 9. 2026)

Mapper v `sif-emit` + ověření v `sif-status` dorovnávají body 1–7 a 9.
Testovací klíč firmy patří **jen** do Edge secrets (`SIF_API_KEY`), ne do Flutteru.
Po create se ukáže QR (data-URI) a odkaz AEAT (`sif_aeat_url`).

| # | Oni | Stav v kódu |
| --- | --- | --- |
| 1–2 | `fecha_expedicion` dnešek Madrid `DD-MM-YYYY`; `fecha_operacion` = `facturas.fecha` | hotovo; den expedice v `sif_fecha_expedicion` |
| 3 | částky `"21"` / `"200"` | hotovo (`amountString`) |
| 4 | `Idempotency-Key` = `facturas.id` | hotovo |
| 5 | create = `Pendiente` | hotovo; `emitida` až Ověřit |
| 6 | QR = base64 | ukládáme data-URI |
| 7 | F1 bez `nif`+`nombre` padá | 400 `destinatario_required` |
| 8 | emisor = API key firmy | pořád jeden `SIF_API_KEY` na projekt — OK do druhé kanceláře |
| 9 | vendor jen Verifacti | jiný vendor = `unsupported_vendor` |

Co je v pořádku: Bearer mimo Flutter, žádný emisor NIF v těle create, `can_access_tenant`, přijaté se sem neposílají.

---

## Jak nasadit (pořadí)

1. **SQL `0043_sif_status.sql`** + deploy Edge `sif-emit`, `sif-status`.
2. **Účet Verifacti** — testovací empresa, klíč jen do Edge secrets (`SIF_VENDOR=verifacti`, `SIF_API_URL=https://api.verifacti.com`, `SIF_API_KEY`). Flutter ne. `GET /verifactu/health`.
3. **Jedna sandbox F1** — Emitir (fronta `pendiente`) → Ověřit (`GET /verifactu/status` podle uuid). QR je data-URI. Teprve `Correcto` → `emitida`.
4. **Edge proxy `GET /verifactu/declaracion`** — stáhnout v Nastavení / Faktury. Souběžně text **DR Sanfolia** (CPF volá CF Verifacti, verze API) — právník, ne marketing.
5. **Produkce** — placený NIF, modelo de representación, produkční klíč firmy. Testovací klíč v produkci ne.
6. **Druhý tenant** — klíč firmy v trezoru tenanta, ne jeden env na celý Sanfolio.

Anulace a rectificativas (R1…) až umíme `cancel` + novou řadu. `modify` (subsanar) není tichý edit v knize.

---

## Právník (neodkládat za kód)

AEAT neschvaluje software. Výrobce SIF podepíše DR. Mixed architecture: DR má Verifacti **i** Sanfolio (voláme tento SIF, tato verze). `GET /verifactu/declaracion` je jejich PDF; naše DR je zvlášť. Povinnost: společnosti 1. 1. 2027, autónomos 1. 7. 2027.

---

## Mimo rozsah (beze změny)

Hash chain, QR kreslení a XML v `carpeta`. Přijaté → AEAT. Vlastní SIF-app. TicketBAI. PGC. JSON page-builder. AI Emitir.
