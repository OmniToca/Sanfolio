# Produktová bible

Zdroj pravdy pro entity, role a hranice. Staff UI je vícejazyčné (`cs`/`en`/`es`/`de`/`fr`), výchozí kancelář partnera = **čeština**. Názvy entit v kódu a DB zůstávají španělské identifikátory (NIE, escritura). Tento dokument je česky.

## 1. Co produkt je

**Gestoría OS** je provozní systém malé španělské gestoría. Nahrazuje tiskárnu, tužku a šanon.

Design partner tiskne ke každé složce dva listy. Tužkou označí, co za klienta řeší. Po digitalizaci stejná deska:

- drží všechna pole z papíru,
- ví, který blok je zapnutý,
- vidí chybějící data a dokumenty,
- hlídá termíny,
- nachystá výzvu klientovi (odesílá gestor).

Není to účetní deník, není to a3, není to GestoLab.

## 2. Slovník

| Entita | Španělsky v UI | Význam |
| --- | --- | --- |
| Tenant | Despacho | Kancelář = zákazník našeho SaaS |
| Usuario | Usuario | Zaměstnanec kanceláře nebo Support |
| Cliente | Cliente | Osoba nebo firma, pro kterou kancelář pracuje |
| Inmueble | Inmueble | Byt / dům / pozemek; nese escritura |
| Expediente | Expediente | Jeden úkon z katalogu nad klientem (volitelně nad nemovitostí) |
| Bloque | Bloque | Položka ze šablony desky (Agua, Luz, Poder, …) se stavem tužky |
| Documento | Documento | Sken / foto. Chybějící **typ** je entita, ne prázdný upload |
| Plazo | Plazo | Termín (odvozený nebo ruční) |
| Mensaje | Mensaje | Návrh nebo odeslaná zpráva klientovi |
| Provisión | Provisión de fondos | Záloha vs. faktura kanceláře (tři čísla, ne účetnictví) |
| Identificador | NIE / DNI / NIF | Normalizovaný identifikační údaj s maskovaným hledáním |

## 3. Vztahy

```
Tenant 1──* Cliente
Cliente 1──* Inmueble
Cliente 1──* Expediente
Cliente 1──* ClientContact     (druhá osoba + locale)
Inmueble 0──* Expediente
Expediente 1──* Bloque
Bloque 0──* Documento
Bloque 0──* Plazo
Cliente 0──* Documento          (DNI, iban justificante — bez bloku)
Plazo 0──* Mensaje
Expediente 0──* Provisión movimiento
```

Klient bez nemovitosti je platný (např. jen NIE / poder / renta).  
Klient bez NIE je platný — první úkon může být vyřízení NIE.  
Nemovitost bez klienta není.  
Expediente typu koupě/prodej skoro vždy nese `inmueble_id`.  
Policie / magistrát / testament: stejný vztah (visí na klientovi); u Jarky moduly zapnuté, desky až po papírové složce.

## 4. Cliente

Karta klienta je hub. Pole z listu 1:

| Pole | Povinné v MVP | Poznámka |
| --- | --- | --- |
| `nombre` / `apellidos` nebo `razon_social` | ano (jedno z) | Fyzická vs. právnická |
| `kind` | ano | `persona` \| `empresa` |
| `nie` / `dni` / `nif` | ne | NIE při založení nemusí. Masky z úřadu (`Y123**6E`) často. |
| `email` | ne | Kanál e-mailu |
| `tel` | ne | WhatsApp / telefon |
| `direccion` | ne | Může se lišit od adresy inmueble |
| `iban` | ne | povinný **jen** kvůli inkasu |
| `locale` | ano, default z `tenant_settings.default_client_locale` | Jazyk komunikace (cs/en/de/fr/es). Překlad zpráv cílí sem. |
| `status` | ano | `activo` \| `inactivo` — ~400 neaktivních schovat, nesmazat |
| `notas` | ne | Volný text kanceláře |

Identifikátory jsou **samostatné řádky** (`client_identifiers`), ne jedno pole. Klient může mít NIE i pas. Hledání viz [search_spec.md](search_spec.md).

Druhý kontakt: `client_contacts` (jméno, vztah, tel, e-mail, **locale, kterým mluví**). Občas.

Soft-delete klienta nesmaže historii expedientes. Neaktivní (`inactivo`) jsou schovaní v seznamu, ne smazaní. Support / owner umí obnovit soft-delete.

## 5. Inmueble

Nese to, co papír píše u ESCRITURA, plus adresu bytu.

| Pole | Povinné když je blok escritura zapnutý | Poznámka |
| --- | --- | --- |
| `direccion` | ano | Adresa nemovitosti |
| `notario` | ne | Jméno notáře |
| `escritura_fecha` | ne | Spouštěč plusvalía |
| `protocolo` | ne | Číslo protokolu |
| `referencia_catastral` | většinou | Gestorie Jarka ji obvykle má |

Jeden klient může mít více nemovitostí. Šablona desky se instancuje **na expediente vázané k inmueble**, ne globálně na osobu (jinak by Agua z bytu A spadla na byt B).

## 6. Expediente

Katalog úkonů z náčrtu:

| Kód | MVP | Papír |
| --- | --- | --- |
| `compraventa` | ano | Celá 2stránková deska |
| `suministros_seguros` | ano jako součást desky, ne nutně samostatný spis | Agua…Alarma |
| `impuestos_ibi` | ano (plazo + checklist) | SUMA / IBI |
| `impuestos_210` | ano (plazo + checklist) | modelo 210 |
| `impuestos_renta` | ano (plazo + checklist) | renta / IRPF |
| `nie_tramite` | ano jako blok Extra, může být i samostatný spis | EXTRAS NIE |
| `poder` | ano jako blok | EXTRAS PODER |
| `policia` | modul zapnutý, deska později | náčrt — Jarka dělá |
| `ayuntamiento` | modul zapnutý, deska později | náčrt — Jarka dělá |
| `testament` | modul zapnutý, deska později | náčrt — Jarka dělá |
| `otros` | ne | náčrt |

Stavy expedientes: `abierto` → `en_curso` → `espera_cliente` → `espera_admin` → `hecho` → `archivado`. Soft-delete je mimo tyto stavy (`deleted_at`).

## 7. Bloque (tužka)

Blok je instance položky šablony u konkrétního expedientes. Stroj stavů a seznam bloků: [folder_template.md](folder_template.md).

Pravidlo: **vypnutý blok neexistuje v inboxu**. Zapnutý blok bez povinných polí je `missing_data`. Zapnutý s poli bez dokumentu je `missing_document`. Zapnutý kompletní s budoucím termínem je `watching`. Zapnutý kompletní bez dalšího termínu je `done`.

Odvození stavu je **serverové** (z polí a dokumentů), ne ruční barvička. Gestor smí stav přebít jen explicitním `done` / `off` s důvodem v auditu.

## 8. Documento

Každý dokument má:

- `tipo` z katalogu (např. `contrato_luz`, `copia_escritura`, `dni_nie`)
- `bloque_id` XOR `cliente_id` (případně obojí, když DNI visí na klientovi)
- soubor v Supabase Storage (EU)
- `uploaded_by`, `created_at`
- `deleted_at`

Chybějící dokument = v šabloně bloku je `required_document_types` a žádný živý dokument tohoto typu.

AI může navrhnout `tipo` a pole z OCR. Zařazení potvrdí gestor.

Dokument = **originál ve Storage** + **přepis v DB** (pole po Guardar, později text PDF). Chat kanceláře čte pole a `plazos`, ne binárku. Fáze: [roadmap_dokumenty_ai.md](roadmap_dokumenty_ai.md).

## 9. Plazo

Termín je řádek s `due_on`, `source` (`derived` \| `manual`), `kind`, `bloque_id` / `expediente_id`.

Odvozené termíny se přepočítají při změně zdrojového pole (např. `escritura_fecha`). Ruční termín se přepisem neodvodí, dokud gestor neřekne „obnovit z pravidla“.

Soft-delete platný. Audit každé změny data.

Pravidla: [deadline_engine.md](deadline_engine.md).

## 10. Mensaje

Žádné tiché odeslání z cronu v MVP bez šablony a bez stopy. Cron **nachystá návrh** (`status = draft`). Gestor klikne Odeslat (`sent`) nebo Zahodit (`discarded`, soft).

MVP kanál: e-mail + **Copiar WhatsApp**. Do klienta jde **překlad** (`send_translated_outbound`). Originál ve spisu. WhatsApp API = v2. AI draft nachystá, odesílá gestor.

## 11. Provisión de fondos y factura

Tři čísla na expediente, ne kniha:

- `recibido_cents`
- `facturado_cents`
- `saldo_cents` = přijato − vyúčtováno (generovaný / trigger)

Pohyby (`provision_movements`): `ingreso` | `factura` | `ajuste`. Inbox upozorní, když `saldo <= 0` a existuje otevřená práce, nebo když práce `hecho` a `facturado = 0`.

Žádné DPH výpočty, žádný VeriFactu, žádné asientos.

## 12. Role

### Support (náš tým)

| Role | Smí |
| --- | --- |
| `support` | Tenant CRUD, licence, onboarding, impersonace s důvodem |

Support **bez** impersonace nečte klienty kanceláře.

### Gestoría (tenant)

| Role | Smí |
| --- | --- |
| `owner` | Vše v tenantu včetně obnovy soft-delete a uživatelů |
| `gestor` | Klienti, spisy, dokumenty, odesílání zpráv, ne správa licence |
| `asistente` | Stejné čtení, zápis dokumentů a polí; nesmí mazat expedientes ani odesílat bez kontroly gestora (MVP: odesílat smí, mazat ne) |

Budoucí `cliente_final` (portál klienta) v MVP neexistuje.

## 13. Non-goals (závazné NO)

- Účetní deník, PGC, asientos
- Výpočet a XML podání modelo 210 / renta / 303
- Vlastní VeriFactu SIF
- 21 EX formulářů
- WhatsApp Business API (copy-to-WhatsApp ano)
- Digitální podpis
- Portál klienta (v2; model zpráv už originál + překlad)
- Nativní aplikace, offline, Drift
- Samostatné desky policie / magistrát / testament před tím, než deska koupě žije v prohlížeči
- Výpočet daně 210 / renta (checklist + plazo ano)
- Fyzické DELETE business dat
- AI s tools `save_*` / `delete_*` / `send_*`

## 14. Jazyk a stack (až kód)

- Flutter web + Dart, Riverpod, GoRouter
- Supabase: Postgres, Auth, Storage, Edge Functions
- i18n: cs/en/es/de/fr ve staff app; výchozí kancelář = čeština; každý člověk `profiles.locale`
- Žádný IndexedDB backlog

Lekce z FalcoNest / LeoDejvIT / OmniToca jsou v [tenancy_audit.md](tenancy_audit.md).
