# Plán: Verifacti API (SIF mimo jádro)

Smlouva z 13. 9. 2026. Kód se k tomuto souboru chová jako k migraci: změna dodavatele nebo rozsahu = změna tohoto souboru ve stejném PR.

**Cíl:** vydané faktury z Sanfolia půjdou na AEAT přes **[Verifacti](https://www.verifacti.com/precios)** (`POST /verifactu/create` …). Uživatel musí umět stáhnout **declaración responsable** z programu — `GET /verifactu/declaracion` ([OpenAPI na stránce cen](https://www.verifacti.com/precios#/paths/~1verifactu~1declaracion/get)).

**Není v tomto plánu:** hash/QR/XML v Flutteru, SIF v `carpeta`, přijaté faktury do AEAT, vlastní SIF-app, TicketBAI, PGC.

Architektura a due diligence: [facturacion_verifactu.md](facturacion_verifactu.md). Audit API vs. `sif-emit`: [audit_verifacti.md](audit_verifacti.md).

---

## Stav teď (neplánovat znovu)

- Modul `facturacion`: kniha **přijatých** (extract + Guardar, žádný SIF) + **koncepty** vydaných.
- Edge `sif-emit` skládá Verifacti JSON (`DD-MM-YYYY`, `Idempotency-Key`, F1 s NIF příjemce). Po 200 je `pendiente`, ne `emitida`.
- Edge `sif-status` (tlačítko **Ověřit**) čte `GET /verifactu/status`. `emitida` až AEAT přijme.
- Bez `SIF_API_URL` / `SIF_API_KEY` obě funkce vrátí `sif_not_configured`. Živý klíč ještě není.
- AI: prefill. Emitir / Ověřit / Guardar jen člověk. Klíč a AEAT mimo klienta.

---

## Rozhodnutí: Verifacti

Napojujeme **toto** API, ne verifactuapi.es ani Asesorio, dokud tenhle soubor neřekne jinak.

| Co | Endpoint | Proč |
| --- | --- | --- |
| Declaración responsable | `GET /verifactu/declaracion` | AEAT: DR musí jít stáhnout z programu. Mixed architecture = DR Verifacti **i** DR Sanfolia (voláme tento SIF, tato verze). |
| Emitir | `POST /verifactu/create` | Koncept `facturas` (emitida) → huella, QR, fronta AEAT u nich. |
| Stav | `GET /verifactu/status` | Po Emitir; Flutter jen ukáže. |
| Anulace | `POST /verifactu/cancel` | Storno + nová, ne tichý edit. |

Ceník a sandbox: [verifacti.com/precios](https://www.verifacti.com/precios). Colaborador social, TicketBAI zvlášť — TicketBAI **není** první tah.

Právník/daňový poradce potvrdí text DR u konkrétní verze API. Marketing nestačí.

---

## Pořadí (až kód)

Mapper create + Ověřit (`sif-status`) jsou v kódu. **Než půjde živý klíč:** aplikovat `0043_sif_status.sql`, nasadit `sif-emit` a `sif-status`, secrets jen na Edge. Detail: [audit_verifacti.md](audit_verifacti.md).

1. Účet Verifacti, testovací empresa, `GET /verifactu/health`. API key emisoru v Edge secrets (`SIF_VENDOR=verifacti`, `SIF_API_URL=https://api.verifacti.com`, `SIF_API_KEY`). Flutter je nevidí. Jeden globální klíč stačí, **dokud emituje jedna kancelář**.
2. Stáhnout DR (`GET /verifactu/declaracion`) a nabídnout ke stažení v Nastavení / Faktury — viditelné pro staff. Vedle toho vlastní DR Sanfolia (CPF volá tento SIF, tato verze) — právník.
3. Jedna testovací F1 z testovacího NIF: Emitir → `pendiente` → **Ověřit** (`GET /verifactu/status`). Teprve `Correcto` / přijetí AEAT nastaví `emitida`.
4. `POST /verifactu/cancel`. Přijaté do tohoto API nepatří.
5. Produkce: placený NIF, modelo de representación, produkční klíč firmy. Druhý tenant = klíč per kancelář, ne sdílený env.

Veřejné docs webhooky nemají — první cesta je poll. `create_bulk`, `modify`, XML export a TicketBAI nejsou V1.

Do jádra Sanfolia VeriFactu ne. Do DocuDocu klonu v `carpeta` ne.
