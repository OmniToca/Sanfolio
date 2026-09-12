# Vyhledávání identifikátorů

Cíl: úřad pošle `Y123**6E` a kancelář najde klienta `Y123456E`. Stejný motor platí pro DNI, NIF/CIF a pas.

Hledání je **first-class** od dne 1 (ne „FTS později“). Inspirace: FalcoNest `search_vector` + GIN, tady navíc masky a trigram.

## 1. Normalizace

Funkce `normalize_id(raw text) → text`:

1. `trim`
2. uppercase
3. odstranit mezery, `-`, `.`, `/`
4. nahradit vizuální masky na kanonickou `*`: `•`, `·`, `x`/`X` **uvnitř** číselné části, `?`, `#`
5. písmena NIE/DNI (prefix X/Y/Z a kontrolní písmeno) se **nesmí** zkonvertovat na `*` jen proto, že OCR řeklo `x`

Příklad: `y-123 45*6-e` → `Y12345*6E`.

Uložené hodnoty:

| Sloupec | Obsah |
| --- | --- |
| `value_raw` | jak přišlo |
| `value_normalized` | výsledek `normalize_id` |
| `value_pattern` | `value_normalized` kde `*` zůstane; pro LIKE |
| `kind` | `nie` \| `dni` \| `nif` \| `passport` \| `nss` \| `other` |

Tabulka `client_identifiers` (soft-delete, `tenant_id`, unique živý `(tenant_id, kind, value_normalized)` tam, kde `value_normalized` **neobsahuje** `*`).

Neúplné / maskované číslo **smí** existovat jako identifikátor (přišlo z úřadu). Nesmí ale kolidovat unique s plným číslem — unique jen na záznamech bez `*`.

## 2. Detekce druhu

Po normalizaci:

| Vzor | `kind` |
| --- | --- |
| `^[XYZ][0-9*]{7}[A-Z]$` | `nie` |
| `^[0-9*]{8}[A-Z]$` | `dni` |
| `^[A-HJ-NP-SUVW][0-9*]{7}[0-9A-J]$` | `nif` (CIF) |
| jinak | `other` / `passport` ručně |

Kontrolní písmeno NIE/DNI (modulo 23, Y→1, X→0, Z→2) se počítá **jen** když v čísle není `*`. Výsledek:

- `checksum = valid` | `invalid` | `unknown`
- `invalid` je **varování**, ne odmítnutí uložení (OCR i úřad chybují)

## 3. Dotaz z UI / AI

Vstup uživatele jde přes stejné `normalize_id`. Pak se skládá skóre (vyšší vyhraje). Tenant filtr vždy.

### 3.1 Přesná shoda — skóre 100

```sql
value_normalized = :q
```

### 3.2 Maskovaný vzor — skóre 90

Dotaz nebo uložená hodnota obsahuje `*`.

Převod na SQL LIKE: `*` → `_` (jeden znak). NIE má pevnou délku 9, takže `Y123**6E` → `Y123__6E`.

Hledání oběma směry:

```sql
-- úřad maskovaný, DB plné
value_normalized LIKE translate(:q, '*', '_')   -- pouze pokud :q má *
-- DB maskované, úřad plné
:q LIKE translate(value_normalized, '*', '_')
```

Postgres: bezpečnější vlastní funkci `id_mask_match(a, b)`:

- stejná délka po normalizaci (NIE 9, DNI 9)
- na každé pozici: znaky rovny, nebo jeden z nich `*`

To pokryje `Y123**6E` vs `Y123456E` i `Y123456E` vs `Y123**6E`.

### 3.3 Trigram — skóre 50–80

Rozšíření `pg_trgm`. GIN index na `value_normalized`.

```sql
value_normalized % :q          -- similarity > threshold
ORDER BY similarity(value_normalized, :q) DESC
```

Práh `0.4` na start (ladit na reálných NIE). Slouží překlepům (`Y123456E` vs `Y123457E`), ne jako náhrada masek.

### 3.4 Fulltext jména a kontaktu — skóre 40

`search_vector` (generated tsvector, config `simple`) na `clientes`: jméno, e-mail, telefon, dirección, protocolo nemovitosti.

```sql
search_vector @@ plainto_tsquery('simple', :q)
```

GIN index `idx_clientes_search`.

### 3.5 IBAN a protocolo

Doplňkové exact/normalize: IBAN bez mezer uppercase; `protocolo` jako text.

## 4. RPC

Jediný vstup z aplikace: `search_clients(p_q text, p_limit int default 20)`.

Vrací `cliente_id`, `score`, `matched_via` (`id_exact` | `id_mask` | `id_trgm` | `fts` | `iban` | `protocolo`), `highlight`.

RLS: funkce `SECURITY INVOKER` + běžné politiky tenantu, nebo `SECURITY DEFINER` s `auth.uid()` a `tenant_id` z membership — preferovat invoker.

Soft-delete: default `deleted_at IS NULL`. Owner může `include_deleted`.

Každé volání z UI detailu (otevření karty) není search; search se loguje do auditu jako `client.search` s hashem dotazu, **ne** s plným NIE v plaintextu pokud lze (MVP: plaintext v auditu je přijatelný uvnitř tenantu, přístup jen owner/support).

## 5. Indexy

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX idx_client_identifiers_normalized
  ON client_identifiers (tenant_id, value_normalized)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_client_identifiers_trgm
  ON client_identifiers USING gin (value_normalized gin_trgm_ops)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_clientes_search
  ON clientes USING gin (search_vector)
  WHERE deleted_at IS NULL;
```

## 6. Příklady

| Dotaz | V DB | Via |
| --- | --- | --- |
| `Y123456E` | `Y123456E` | exact |
| `Y123**6E` | `Y123456E` | mask |
| `Y123456E` | `Y123**6E` | mask |
| `***4567*` (DA 7ª styl) | `Y1234567E` — **délka nesedí na 9** | ne NIE-mask; zkusit FTS / ruční |
| `y 123-456 e` | `Y123456E` | exact po normalize |
| `García` | jméno | fts |

AEPD DA 7ª publikuje 4 číslice (`****4567*`). To **není** stejné jako `Y123**6E`. Mask matcher s rozdílnou délkou v MVP nehádá — vrátí trigram + FTS kandidáty a gestor vybere. Rozšíření na DA 7ª = v2.

## 7. AI

Tool `search_clients` volá totéž RPC. Nesmí dostat raw SQL. Výsledek max 20 řádků. Další krok je `open_screen`, ne tichý update.
