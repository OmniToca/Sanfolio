# Plán: titulares na inmueble (ne druhý kontakt)

Smlouva z rozhovoru 13. 9. 2026. Kód se k tomuto souboru chová jako k migraci: změna pořadí nebo rozsahu = změna tohoto souboru ve stejném PR.

**Cíl:** podíl na finca žije u nemovitosti. 210 vezme `sharePercent` z řádku titulare tohoto klienta na tomto inmueble. Papír (extract) navrhne. Gestor uloží.

**Není v tomto plánu:** NIE na `client_contacts`, druhá carpeta pro spoluvlastníka, Catastro API, AEAT XML, modelo 211, IBI split, JSON page-builder, AI save.

Kupující z listiny **dostane kartu** (hledání, e-mail). Nedostane desku. Složka zůstane u `inmuebles.cliente_id`.

---

## Stav teď (neplánovat znovu)

Hotovo T0–T4 v kódu (2026-09-13): tabulka `inmueble_titulares`, Guardar listiny zapíše strany (jen když je finca prázdná), šanon ESCRITURA opraví %, 210 doplní `sharePercent` z titulare tohoto klienta. T5: karta spoluvlastníka bez druhé desky.

- `client_contacts` = komunikace (partner, překladatel, locale, WhatsApp). Bez NIE, bez %.
- Vlastnictví = `inmueble_titulares` (NIE, jméno, cuota, právo, od–do). Daně = osoba × podíl té finca.
- `inmuebles.cliente_id` = **složka kanceláře** (pro koho vedeme desku). Není to „jediný vlastník“.
- Nemovitost jen B+C nepatří do složky klienta A.
- Druhá karta (kupující) vznikne z listiny jako klient bez carpeta. Unique NIE (`uq_client_identifiers_live`) jen naváže existující řádek.
- AI: extract / prefill. INSERT/UPDATE titulares jen gestor (Guardar nebo tužka na šanonu).
- `fields.holder` na agua/luz/gaz = kdo platí fakturu. Není cadastral titular.
- `fields.cuota` na 210 = daň v centech. Podíl je `fields.sharePercent` / v DB `cuota_bps`.
- Český manželský režim v listině ≠ gananciales. Default = stejný díl mezi kupujícími, dokud gestor neopraví.

Španělské právo (proč tabulka, ne kontakt): CC 392–393 proindiviso; Catastro RDL 1/2004 art. 9 (každý comunero + cuota); modelo 210 `cuota de participación %` (manželé nerezidenti výjimka tipo 28); modelo 211 3 % jen z podílu nerezidenta; IBI TRLRHL 63; plusvalía 106 (u nerezidenta FO může být nabyvatel sustituto).

---

## Jak to naprogramujeme

### Data

Nová tabulka `inmueble_titulares` (ne sloupec JSON na `inmuebles`, ne pole na `cliente_snapshot`):


| Sloupec                      | Typ                           | Proč                                                                                  |
| ---------------------------- | ----------------------------- | ------------------------------------------------------------------------------------- |
| `id`                         | UUID                          | jako všude                                                                            |
| `tenant_id`                  | UUID                          | RLS `can_access_tenant`                                                               |
| `inmueble_id`                | UUID FK                       | podíl patří finca, ne kartě                                                           |
| `lado`                       | `comprador` | `vendedor`      | 210 čte živé kupující; 211/plusvalía později prodávající                              |
| `derecho`                    | TEXT, default `pleno_dominio` | později usufructo; teď jediná hodnota                                                 |
| `nombre`                     | TEXT NOT NULL                 | z listiny                                                                             |
| `nie_raw` / `nie_normalized` | TEXT                          | stejná normalizace jako `normalize_id`; prázdný NIE povolen (kancelář začíná bez něj) |
| `cuota_bps`                  | INT                           | 50 % = 5000. Integer, ne float. 1–10000                                               |
| `cliente_id`                 | UUID NULL FK                  | jen když už je kartou kanceláře                                                       |
| `desde`                      | DATE NULL                     | obvykle `escritura_fecha`                                                             |
| `deleted_at`                 | timestamptz                   | soft-delete                                                                           |
| `created_at` / `updated_at`  |                               | jako `client_contacts`                                                                |


Index živých: `(inmueble_id) WHERE deleted_at IS NULL`.  
Unique živých s NIE: `(inmueble_id, nie_normalized) WHERE deleted_at IS NULL AND nie_normalized <> ''`.  
Žádný unique NIE napříč tenantem tady — Monika může být na dvou bytech.

Součet `cuota_bps` u živých `comprador` **není** CHECK. UI varuje, když ≠ 10000 (1/3 = 3333+3333+3334). Usufructo později součet rozbije jinak.

RLS, `set_updated_at`, `forbid_hard_delete`, audit trigger jako `client_contacts`. `cliente_audit_log` napojí přes `inmuebles.cliente_id`, ať stopa na kartě Petra ukáže i Moniku jako titular, ne jako kontakt.

`inmuebles.cliente_id` se **nemění**. Seed `open_carpeta_compraventa` / `add_inmueble_compraventa` tabulku netýká (prázdná).

### Extract → návrh → uložení

Dnes už Guardar listiny:

1. zapíše `documentos.extracted` (`fields.buyers` / `sellers` / catastral…),
2. na desku `escritura` jen notář / datum / protokol,
3. na `inmuebles` finca, notář, datum,
4. na `cliente_snapshot` NIE **jen** když `documentFitsCliente`.

To zůstane. Titulares jsou **pátý** zápis, oddělený:

- Návrh = parse `DeedPerson` z extractu (ne string `fields.buyers` jako zdroj po prvním uložení).
- Kupující → `lado=comprador`, `cuota_bps` = `10000 ~/ n`, zbytek na posledního.
- Prodávající → `lado=vendedor` (pro pozdější 211). Do 210 se nepletou.
- `cliente_id` vyplň **jen** match NIE na existující `client_identifiers` téhož tenantu (Petr). Moniku nelinkuj, dokud nemá kartu.
- Zápis řádků **jen** když na inmueble ještě není živý titular (idempotentní Guardar nesmí duplikovat ani přepsat ruční opravu).
- Když už řádky jsou, Guardar listiny je nechá. Gestor edituje tužkou na šanonu.

AI `extract-document` dál jen `ai_drafts`. Edge **neinsertuje** titulares.

### UI

Šanon `/clientes/:id/carpeta/escritura` (ne tlačítko Druhý kontakt). Sekce „Titulares“: jméno, NIE, %, strana, badge když `cliente_id` = složka. Tužka opraví %. Soft-delete řádku. Přidat ručně (bez NIE ok).

Karta klienta: kontakty beze změny. Žádný dump kupujících.

210 deska: `_withInmuebleFacts` doplní `fields.sharePercent` z živého `comprador` jehož `cliente_id` = spis **nebo** NIE sedí na identifikátoru klienta. Stejné pravidlo jako adresa: jen když pole zeje. Fallback 100 % (dnešní `_percent`) zůstane, dokud řádek není.

Volitelně později: u jiného kupujícího tlačítko „Otevřít / založit kartu“ (hledání NIE, unique). Není T1–T4.

### i18n

Klíče v `cs/en/es/de/fr`. Úřední slova (titular, cuota, NIE) v UI nepřekládat pryč — popisek ano (`fields.sharePercent` už je).

---

## Audit: co nesmíme rozbít

Kontrola proti kódu 13. 9. 2026. Každá fáze po testu projde tento seznam.

### Nesahat


| Místo                                      | Proč by to prasklo                                                                                                                     |
| ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| `inmuebles.cliente_id`                     | `open_carpeta_compraventa`, `add_inmueble_compraventa`, storage `{tenant}/{cliente}/…`, inbox, 210 `linksInmueble`. Složka ≠ vlastník. |
| `client_contacts` schema/UI                | Bez NIE, audit `client_contacts.*`, locale. Spoluvlastník tam = špatná daň i LOPDGDD.                                                  |
| `uq_client_identifiers_live`               | INSERT druhé karty s Moničiným NIE spadne nebo přepíše Petrův identifikátor.                                                           |
| `_persistCliente`                          | Guardar snapshotu nesmí dostat prodávajícího NIE (už hlídá `documentFitsCliente`). Titulares sem nepatří.                              |
| `promotePaperToDesk`                       | Escritura šablona má jen notary/date/protocol. Buyers na desku ne.                                                                     |
| `fields.holder`                            | Identita dodávky. Recompute agua/luz vyžaduje holder.                                                                                  |
| `fields.cuota`                             | Výstup 210 v centech. Pojmenovat podíl `cuota_bps` / `sharePercent`.                                                                   |
| `modelo_210.dart` formule                  | `scaleCents` už krátí základem × share. Měnit jen **zdroj** sharePercent, ne vzorec.                                                   |
| `add_inmueble_compraventa`                 | Nová finca = prázdní titulares. Nekopírovat z bytu A.                                                                                  |
| Soft-delete / audit append-only            | Žádný DELETE, žádný AI zápis.                                                                                                          |
| `query_escritura` / `search_document_text` | Strany už jsou v `extracted` + `body_text`. T1–T3 SQL tool nemění.                                                                     |
| Inbox / plazos IBI a plusvalía             | Visí na `inmueble.escritura_fecha` + `cliente_id` složky. Titular to nespouští.                                                        |


### Musí dál platit

- Guardar na kartě klienta u listiny **neplní** `inmuebles` (to dělá jen deska/šanon). T2 zápis titulares jen z `CarpetaController.saveDocumentoExtracted`, ne z `ClienteCardController`.
- Jedna carpeta = jeden `inmueble_id` na compraventa. Titulares toho inmueble, ne „všichni lidé na kartě“.
- 210 bez navázaného inmueble: sharePercent ručně, jako dnes.
- Klient bez NIE: titular může mít prázdný NIE; match na kartu přes `cliente_id` složky (jméno).
- `recompute_bloque_status` u escritura: povinný doklad `copia_escritura`, ne počet titulares. Blok nesmí spadnout do `missing_data` kvůli prázdné tabulce.
- Existující byty (Petr / Islandia 14): T1 = prázdná tabulka, 210 dál 100 % dokud gestor neuloží podíly. Žádný backfill z `extracted` v migraci (mohlo by vzít starý špatný extract).

### Rizika a pojistka

1. **Guardar 2×** → unique (inmueble, NIE) + „zapisuj jen když count živých = 0“.
2. **Extract splete stranu** → UI na šanonu hned po Guardar; vendedor ≠ 210 share.
3. **Dva klienti, jedna finca** (Petr i Monika mají kartu) → dva expedientes 210, stejné `inmueble_id`, jiný `cliente_id`. Titular.cliente_id odliší share. **Toto v T1–T4 neřešíme založením karty**, jen schématem to nesmí znemožnit (`cliente_id` nullable, inmueble má pořád jednoho folder owner).
4. **Složka Petra, koupě jen Monika** — nestává se v happy path; gestor nesmí auto-přepsat `inmuebles.cliente_id`.
5. **Třetina** — zbytek bps na posledního; test.
6. `**ai_get_cliente**` — T4 smí přidal read-only titulares do snapshotu; žádný write tool.

---

## Fáze (jedna = sloučitelný kus, pak ověření na webu)

Stejná brána jako u dokumentů: `cd apps/gestoria && flutter test`. SQL+Edge v tom samém PR jako `docs/`. Další fázi nezačínáme, dokud předchozí drží na [sanfolio-os.netlify.app](https://sanfolio-os.netlify.app).

### T0 — Smlouva (tento soubor)

Hotovo když: bible, šablona složky a slovník říkají totéž co tahle migrace. Žádný kód.

### T1 — Tabulka, ticho

**Proč první:** UI bez schématu zase skončí v JSON na bloku.

- Migrace `0037_inmueble_titulares.sql`: tabulka, RLS, trigger, unique, grant authenticated.
- `docs/database_schema.md` + řádek ve slovníku.
- Flutter **nečte**. Nic se na webu nemění.

Hotovo když: `supabase db push` na linked projekt; Petrův 210 a deska vypadají stejně.

### T2 — Guardar listiny navrhne řádky

**Proč:** extract už zná Petra + Moniku; bez zápisu to 210 nevidí.

- Parser: `DeedFacts.buyers/sellers` → DTO (nie, name, lado, cuota_bps). Test na fixture Islandia 14 (2 kupující → 5000+5000; 2 prodávající bez cuota do 210).
- `CarpetaController` po úspěšném `_persistInmuebleFromDeed`: pokud 0 živých titulares, INSERT. Match `cliente_id` přes NIE. AI ne.
- Guardar na kartě klienta **ninsertuje** (žádné `inmueble_id` jistoty).
- Idempotence: druhý Guardar no-op.

Hotovo když: u Petra Guardar kopie escritura založí 2 comprador + prodávající; unique NIE klienta se nezmění; `client_contacts` beze změny. Ověřit v Table Editor, ne screenshot.

### T3 — Šanon ESCRITURA

**Proč:** extract umí 50/50 špatně; tužka musí opravit než 210.

- Sekce titulares na `/carpeta/escritura`.
- Edit cuota, soft-delete, ruční přidání.
- Varování součtu ≠ 100 %.
- i18n pět lokalit.

Hotovo když: Jarka změní Moniku na 40 % a po reloadu to sedí. Kontaktní tlačítko na kartě pořád zakládá jen komunikaci.

### T4 — 210 čte podíl

**Proč:** to je daň. Bez toho je tabulka na okrasu.

- `_withInmuebleFacts` (nebo RPC) doplní `fields.sharePercent` z `cuota_bps` (5000 → `"50"`).
- Jen prázdné pole; ruční 100 % se nepřepíše.
- Test: imputace 50 % beze změny formule (`modelo_210_test` už 50 % má — přidat zdroj z titulare).
- `ai_get_cliente` smí titular vypsat read-only.

Hotovo když: Petrův 210 na Islandia 14 po T2+T3 ukáže 50, výpočet jako ručně zadaných 50. Bez titulares = 100 jako dnes.

### T5 — Karta spoluvlastníka (dohledat, ne druhá deska)

**Rozhodnutí:** kupující z listiny **je klient kanceláře** (e-mail, hledání NIE). Není to druhá carpeta a není to `client_contacts`.

- `inmuebles.cliente_id` zůstane složka (Petr). Monika nedostane `open_carpeta_compraventa`.
- Guardar / otevření šanonu ESCRITURA: u každého `comprador` s NIE bez `cliente_id` najít unique NIE v tenantovi, jinak založit `clientes` + identifikátor a navázat. AI ne. Prodávající ne.
- Seznam klientů: kdo nemá vlastní inmueble, ale je titular jinde, má razítko **Spoluvlastník · {složka} · {adresa}**. Složka Petra vypadá jako dřív.
- Její 210 umí vybrat tutéž finca (titular, ne `inmuebles.cliente_id`).
- Tlačítko složky na její kartě otevře **Petrovu** carpeta, ne prázdný spis.

Hotovo když: Guardar u Petra založí Moniku; hledání `Y9737090P` ji najde; seznam není druhá prázdná složka; unique NIE Petra beze změny.

### Později (nečíslovat do T)

Modelo 211 z `vendedor` + cuota; plusvalía sustituto; IBI podle cuota; pohled „kde je Monika titular“ napříč byty; Catastro.

---

## Pořadí závislostí

```
T0 smlouva
 └─ T1 tabulka
     └─ T2 Guardar → řádky
         └─ T3 šanon (oprava %)
             └─ T4 210 sharePercent
                 └─ T5 karta spoluvlastníka (opt.)
```

T3 lze slít s T2 v jednom PR, **jen** když UI stihne varování a testy. T1 sám o sobě, ať rollback schématu není zamotaný ve widgetu.

---

## Ověření u design partnera

Na složce Petr Sokol / Islandia 14 (protocol 2116), ne na syntetickém PDF:

- Guardar listiny: kupující Petr + Monika, ne Patricia.
- Žádný nový `client_contacts` řádek.
- 210 share 50 po T4, daň jako dřív při ručních 50.
- Druhá koupě (`add_inmueble_compraventa`) má prázdné titulares, dokud nemá svou escritura.

