# Produktová bible

Zdroj pravdy pro entity, role a hranice. Staff UI je vícejazyčné (`cs`/`en`/`es`/`de`/`fr`), výchozí kancelář partnera = **čeština**. Názvy entit v kódu a DB zůstávají španělské identifikátory (NIE, escritura). Tento dokument je česky.

## 1. Co produkt je

**Sanfolio** (kód: Gestoría OS) je provozní systém španělské kanceláře — gestoría i asesoría. Jedna data o klientovi, službách, papírech a penězích. Kancelář si zapne **moduly**. Vzor rozsahu: [myUcto.cz](https://myucto.cz) pro Česko (evidence → doklady → podání → banka), tady totéž pro Španělsko.

Gestorie Jarka je **první kancelář**, na které denně ověřujeme, že deska drží. Není strop trhu, není definice produktu a **není podmínka další práce**. Stavíme jednu aplikaci, která musí být dobrá pro jednu kancelář i pro deset. Až bude dost dobrá, nabídneme ji dalším. Do té doby nic nečeká na „až budeme mít druhého klienta“.

### Co každá kancelář dělá

Než se liší (cizinci na Costa Blanca vs. laborál v Madridu), dělá totéž:

1. Ví, **kdo je klient** (jméno, NIE/DNI/NIF, jazyk, kontakty).
2. Ví, **co pro něj dělá** — a co ne. Vypnutá služba se nehlídá.
3. Drží **doklady** (originál + přepis), ne jen poznámku v chatu.
4. Hlídá **termíny** vůči úřadu, dodavateli i sobě.
5. **Mluví s klientem** v jeho jazyce; ve spisu zůstane originál.
6. **Účtuje si práci** a ví, kdo zaplatil.
7. Časem **podává na úřady** a páruje banku — z týchž dat, ne z druhé aplikace.

První vrstva v kódu je 1–5 (evidence + deska + inbox + výzvy). 6 je záloha na desce **a** kniha `facturacion`. 7 (podání AEAT XML, banka, PGC) je na [seznamu vývoje](vyvoj.md). Žádná z těch vrstev neničí jádro. Pořadí je priorita na tom seznamu, ne čekání na dalšího zákazníka.

### Jádro, které se nemění

- Složka / deska je pravda o klientovi a úkonu. Ne obecný CRM a ne účetní deník jako start.
- Služba se **zapíná**. Vypnutá neexistuje v inboxu (v kódu: blok).
- AI hledá, otevírá, navrhuje. Ukládá, maže, odesílá a podává **člověk**.
- Soft-delete, append-only audit, i18n JSON, moduly + sloty. Žádný JSON page-builder.

### První deska (teď)

Ráno **inbox** (`/inbox`): denní smyčka z `inbox_feed` (termíny, díry, záloha). Nad ní bannery, které smyčka neumí (prázdné se schovají, **žádná ikona v railu**): přepisy čekající na Guardar (`/prepis`), kampaně (`/kampane`: 210, koupě po notáři, IBI/SUMA, expirace DNI/pas/poder/seguro), karty bez kanálu (`/kanal`), přeplatky vs. tarify kanceláře (`/preplatek`), dlužné zálohy (`/dluh`), city dne (`/citas`). Pošta má **vlastní položku v railu** (`/posta`), ne banner.

Nový klient: jméno → `/stoh` (stoh skenů ze šanonu), nebo CSV na `/clientes/import` (duplicitní NIE přeskočí, stoh se samo neotevře). AI navrhne blok, Guardar zařadí a zapne službu. Stejný sklad je kdykoli ze složky. AI neukládá.

Přes den **složka klienta** = deska koupě (tužka → bloky → šanon). Modelo 210 se **počítá** na tenkém spisu; podání AEAT ne. Kniha faktur je **modul** `facturacion` (přijaté bez AEAT; vydané přes Verifacti `sif-emit` / `sif-status`). Nabídky kanceláře (`ofertas`) žijí v Nastavení a na bloku luz/gaz/seguro, ne v railu.

Rail (pořadí v kódu): Inbox → Pošta (modul messaging) → Klienti → Faktury (modul facturacion) → Nastavení. **Žádná další ikona.** Nová agenda = slot (`inbox.feed`, `carpeta.blocks`, `settings.section`) nebo složka.

Staff nápověda jednou stranou: [rano_v_kancelari.md](rano_v_kancelari.md). Help center nestavíme.

### Poučení z velkých despachos (ne kopie)

Velké kanceláře (např. Ábaco Advisers: kontrola papírů klienta, HomeSuite s Conveyancing / CRM / mailem / TPV / DMS) ukazují, čím kancelář žije: **honí pojmenované papíry**, ne jednu kupní smlouvu. Sanfolio si bere princip. Jejich plochu, fialovou tabulku ani šestnáct ikon nekopírujeme.

- Úkon se jmenuje podle papírů, které kancelář sbírá (NIE, poder, IBI, dodávky, escritura, případně cédula / residencia), ne podle produktu „Conveyancing“.
- `compraventa` má **tři časy na stejné desce**: před notářem (identita, poder, cédula, IBI, dodávky, komunita) → notář (`escritura`) → po (plusvalía, 210, přepis). Escritura je jeden blok, ne celý úkon. Šablona: [folder_template.md](folder_template.md). Tisk z desky vrátí ty dva listy A4 v prohlížeči (PDF z dialogu tisku).
- Kontrola papírů = stav zapnutého bloku (`missing_document` / inbox / Pedir). Není druhá tabulka „Documentos de control“ a není druhá pravda vedle složky.
- Dědictví (defunción, declaratorio de herederos, testamento) je **jiný spis**, i když sdílí NIE a pas s koupí.
- Do katalogu papírů patří jen to, co kancelář fakt sbírá. Cédula nebo residencia až jako zapnutý blok, ne proto, že je má cizí suite.
- Zákaz: plocha s desítkami programů (CRM, TPV, DMS, účetní deník) jako sourozenci railu. Pošta a kniha faktur jsou v railu, protože to je denní vstup (ingest / Emitir), ne druhá evidence vedle složky. 210, přepisy, nabídky a koupě po notáři **nejsou** ikony.

## 2. Slovník

| Entita | Španělsky v UI | Význam |
| --- | --- | --- |
| Tenant | Despacho | Kancelář = zákazník našeho SaaS |
| Usuario | Usuario | Zaměstnanec kanceláře nebo Support |
| Cliente | Cliente | Osoba nebo firma, pro kterou kancelář pracuje |
| Inmueble | Inmueble | Byt / dům / pozemek; nese escritura |
| Titular | Titular | Spoluvlastník finca (`inmueble_titulares`); NIE + cuota; není druhý kontakt |
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
Cliente 1──* Inmueble           (složka kanceláře, ne jediný vlastník)
Cliente 1──* Expediente
Cliente 1──* ClientContact     (komunikace + locale, ne vlastnictví)
Inmueble 1──* Titular          (NIE, cuota; daně osoby × finca)
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
Nemovitost bez **složky** (klienta kanceláře) není. Spoluvlastník-kupující dostane **kartu** (hledání, e-mail), ne druhou desku. Titulares drží podíl na finca.  
Expediente typu koupě/prodej skoro vždy nese `inmueble_id`.  
Policie / magistrát / testament: stejný vztah (visí na klientovi); u Jarky moduly zapnuté, **tenký spis** (stav + cita + papír), dokud kancelář nechce plnou desku.  
Spoluvlastnictví: [roadmap_titulares.md](roadmap_titulares.md).

## 4. Cliente

Karta klienta je hub. Pole evidence osoby:

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

Druhý kontakt: `client_contacts` (jméno, vztah, tel, e-mail, **locale, kterým mluví**). Občas. Není spoluvlastník — ten je `inmueble_titulares`.

Soft-delete klienta nesmaže historii expedientes. Neaktivní (`inactivo`) jsou schovaní v seznamu, ne smazaní. Support / owner umí obnovit soft-delete.

## 5. Inmueble

Nese to, co patří k finca (adresa, notář, catastral), ne jen poznámka na kartě.

| Pole | Povinné když je blok escritura zapnutý | Poznámka |
| --- | --- | --- |
| `direccion` | ano | Adresa nemovitosti |
| `notario` | ne | Jméno notáře |
| `escritura_fecha` | ne | Spouštěč plusvalía |
| `protocolo` | ne | Číslo protokolu |
| `referencia_catastral` | většinou | Gestorie Jarka ji obvykle má |

`inmuebles.cliente_id` je složka (pro koho kancelář vede desku). **Složka = strana listiny; listina se nedělí.** Podíly na finca jsou `inmueble_titulares` (NIE, `cuota_bps`, lado comprador/vendedor). Čip na desce ukáže stranu této karty. Modelo 210 čte `sharePercent` z titulare tohoto klienta a navrhne `incomeKind` z lado (imputace u kupujícího, transmise u prodávajícího). 211 není blok desky.

Jeden klient může mít více nemovitostí. Šablona desky se instancuje **na expediente vázané k inmueble**, ne globálně na osobu (jinak by Agua z bytu A spadla na byt B). Nemovitost jen B+C nepatří do složky A.

## 6. Expediente

Katalog úkonů z náčrtu:

| Kód | MVP | Papír |
| --- | --- | --- |
| `compraventa` | ano | Deska koupě: balík papírů v čase, ne jen escritura |
| `suministros_seguros` | ano jako součást desky, ne nutně samostatný spis | Agua…Alarma |
| `impuestos_ibi` | ano (plazo + checklist) | SUMA / IBI |
| `impuestos_210` | ano (plazo + checklist + výpočet IRNR) | modelo 210 |
| `impuestos_renta` | ano (plazo + checklist) | renta / IRPF |
| `nie_tramite` | ano jako blok Extra, může být i samostatný spis | EXTRAS NIE |
| `poder` | ano jako blok | EXTRAS PODER |
| `policia` | ano (tenký spis) | stav úkonu + cita + justificante |
| `ayuntamiento` | ano (tenký spis) | stav úkonu + cita + justificante |
| `testament` | ano (tenký spis) | stav úkonu + cita + copia/justificante |
| `otros` | ne | náčrt |

Stavy expedientes: `abierto` → `en_curso` → `espera_cliente` → `espera_admin` → `hecho` → `archivado`. Soft-delete je mimo tyto stavy (`deleted_at`).

Koupě/prodej **není** soubor `copia_escritura`. Je to expediente s bloky, které kancelář zapne. Velká kancelář často nejdřív sežene NIE, pas, poder, IBI a dodávky, a teprve pak jde k notáři. Dědická sada (testamento, herederos) sem nepatří — je to jiný úkon z katalogu.

## 7. Bloque (zapnutá služba)

Blok je instance položky šablony u konkrétního expedientes — „tuto službu pro klienta děláme“. Stroj stavů a seznam bloků: [folder_template.md](folder_template.md).

Pravidlo: **vypnutý blok neexistuje v inboxu**. Zapnutý blok bez povinných polí je `missing_data`. Zapnutý s poli bez dokumentu je `missing_document`. Zapnutý kompletní s budoucím termínem je `watching`. Zapnutý kompletní bez dalšího termínu je `done`.

Odvození stavu je **serverové** (z polí a dokumentů), ne ruční barvička. Gestor smí stav přebít jen explicitním `done` / `off` s důvodem v auditu.

## 8. Documento

Každý dokument má:

- `tipo` z katalogu (např. `contrato_luz`, `copia_escritura`, `dni_nie`)
- `bloque_id` XOR `cliente_id` (případně obojí, když DNI visí na klientovi)
- soubor v Supabase Storage (EU)
- `uploaded_by`, `created_at`
- `deleted_at`

Chybějící dokument = `required_doc_types` a režim `all` (každý typ) nebo `any` (stačí jeden — voda/luz/gaz: faktura bez smlouvy).

AI může navrhnout `tipo` a blok (stoh) i pole z OCR. Zařazení potvrdí gestor.

Dokument = **originál ve Storage** + **přepis v DB** (pole po Guardar, později text PDF). Chat kanceláře čte pole a `plazos`, ne binárku. Fáze: [roadmap_dokumenty_ai.md](roadmap_dokumenty_ai.md).

## 9. Plazo

Termín je řádek s `due_on`, `source` (`derived` \| `manual`), `kind`, `bloque_id` / `expediente_id`.

Odvozené termíny se přepočítají při změně zdrojového pole (např. `escritura_fecha`). Ruční termín se přepisem neodvodí, dokud gestor neřekne „obnovit z pravidla“.

Soft-delete platný. Audit každé změny data.

Pravidla: [deadline_engine.md](deadline_engine.md).

## 10. Mensaje

Žádné tiché odeslání z cronu v MVP bez šablony a bez stopy. Cron **nachystá návrh** (`status = draft`). Gestor klikne Odeslat (`sent`) nebo Zahodit (`discarded`, soft).

MVP kanál: e-mail + **Copiar WhatsApp**. Do klienta jde **překlad** (`send_translated_outbound`). Originál ve spisu. WhatsApp Business API je na [seznamu vývoje](vyvoj.md). AI draft nachystá, odesílá gestor.

## 11. Provisión de fondos y factura

Tři čísla na expediente, ne kniha:

- `recibido_cents`
- `facturado_cents`
- `saldo_cents` = přijato − vyúčtováno (generovaný / trigger)

Pohyby (`provision_movements`): `ingreso` | `factura` | `ajuste`. Inbox upozorní, když `saldo <= 0` a existuje otevřená práce, nebo když práce `hecho` a `facturado = 0`.

Vydaná z knihy (`facturas.direccion = emitida`) s `cliente_id` se **propsuje** na otevřenou zálohu složky (`provision_movements.factura_id`). Tři čísla na desce se zvednou sama. DPH, QR a AEAT zůstávají v knize. Bez karty (F2 ručně) se na složku neváže. Přijatá (`recibida`) je dodavatel na kartě, ne záloha kanceláře.

Tohle je **základní** evidence peněz kanceláře. Modul `facturacion` (licence v `organization_modules`) je **v kódu**: kniha přijatých (extract + Guardar, žádná AEAT) a vydaných. Emitir volá Edge `sif-emit`; **Ověřit** volá `sif-status`. Hash, QR a XML v jádru Sanfolia nestavíme. Účetní deník PGC pořád není.

## 12. Role

### Support (náš tým)

| Role | Smí |
| --- | --- |
| `support` | Tenant CRUD, licence, onboarding, impersonace s důvodem |

Support **bez** impersonace nečte klienty kanceláře.

### Gestoría (tenant)

| Role | Smí |
| --- | --- |
| `owner` | Vše v tenantu včetně obnovy soft-delete, týmu a rozsahu kolegů |
| `gestor` | Default: všichni klienti. Owner smí omezit na karty + bloky (voda/elektřina). Inbox, pošta a AI jen v tom rozsahu. Ne správa licence |
| `asistente` | Stejné čtení v rámci svého rozsahu; neschová expediente |

Portál klienta (`cliente_final`) je na [seznamu vývoje](vyvoj.md); model zpráv už počítá s originálem + překladem.

## 13. Co se nesmí rozbít vs. co přijde jako modul

### Trvalé zákazy (destrukce produktu)

- Fyzické DELETE business dat
- AI s tools `save_*` / `delete_*` / `send_*` / podání na úřad bez kliknutí člověka
- Vlastní VeriFactu SIF (až faktury: certifikovaný poskytovatel, ne stavět SIF v jádru)
- Volný JSON page-builder / drag-drop layout
- Plocha s desítkami programů (CRM, TPV, DMS, deník) vedle railu; agenda patří do složky / slotu. Rail má jen Inbox, Poštu, Klienty, Faktury, Nastavení.
- Nativní aplikace, offline, Drift, IndexedDB backlog
- Hardcoded UI text

### Jak stavíme (žádné „až někdy“)

- Každý nápad se **seřadí podle priority** a jde na [seznam vývoje](vyvoj.md). Pracujeme podle něj, postupně.
- Přijde nový nápad → nejdřív priorita, pak zařazení. Nepřeskakuje frontu jen proto, že je čerstvý, a nečeká na druhého klienta.
- Položka na seznamu je pořád **další licence v `organization_modules`**, ne přepis jádra. Defaultní pořadí vrstev jako myUcto (doklad a klient → podání a peníze → účetnictví), dokud nová položka nedostane vyšší prioritu.
- Trvalé zákazy výše se na seznam **nedávají**. Jsou to hranice produktu, ne odklad.

Živý seznam (co je v kódu, co je ve frontě, jak hodnotíme prioritu): [vyvoj.md](vyvoj.md).

### Horizont modulů

| Vrstva | Příklady | Stav |
| --- | --- | --- |
| Evidence | klient, finca, titulares, papíry, lhůty, výzvy | v kódu |
| Trámites | 210 / IBI / NIE / poder; podání XML na seznamu | výpočet 210 a checklist teď |
| Despacho | kniha faktur + Verifacti adapter; inkaso/banka na seznamu | kniha teď; banka ve frontě |
| Contabilidad | PGC, DPH 303, asientos | na seznamu, defaultně za despacho |
| Vertikály | extranjería EX, tráfico, laborál | jen jako modul, ne přepis jádra |

## 14. Jazyk a stack (až kód)

- Flutter web + Dart, Riverpod, GoRouter
- Supabase: Postgres, Auth, Storage, Edge Functions
- i18n: cs/en/es/de/fr ve staff app; výchozí kancelář = čeština; každý člověk `profiles.locale`
- Žádný IndexedDB backlog

Lekce z FalcoNest / LeoDejvIT / OmniToca jsou v [tenancy_audit.md](tenancy_audit.md).
