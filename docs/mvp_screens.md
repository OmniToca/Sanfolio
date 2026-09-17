# MVP obrazovky

Cíl: paní přestane tisknout dva listy. Ráno inbox, přes den desky klienta = papír.

Všechny texty UI z i18n (`cs` default). Layout: rail vlevo (desktop) + top bar. Breakpoint ~720 px: bottom nav Inbox / Pošta / Klienti / Faktury / Nastavení (Pošta a Faktury jen se zapnutým modulem).

## 1. Mapa rout

### Gestoría app

| Route | Obrazovka |
| --- | --- |
| `/login` | e-mail / heslo, zapomenuté heslo |
| `/reset-password` | nové heslo z odkazu v e-mailu |
| `/inbox` | denní smyčka |
| `/prepis` | fronta přepisů (Guardar) |
| `/kampane` | 210 bez podání + koupě po notáři |
| `/preplatek` | kdo z faktur platí víc než office_offers |
| `/posta`, `/posta/:id` | příchozí pošta |
| `/clientes` | seznam + nové (NIE není povinné) |
| `/clientes/:id` | deska klienta |
| `/clientes/:id/stoh` | stoh skenů ze šanonu; Guardar zařadí na blok |
| `/clientes/:id/carpeta` | dva listy (tužka); bloky kromě klienta jsou kryty |
| `/clientes/:id/carpeta/:bloque` | šanon jednoho bloku: identita + papíry |
| `/clientes/:id/mensaje` | compose výzvy; odeslat = překlad |
| `/expedientes/:id` | úkon (daně, NIE, policía, ayuntamiento, testament) |
| `/facturacion`, `/facturacion/:libro`, `/facturacion/nueva`, `/facturacion/f/:id` | kniha a koncept vydané |
| `/settings` | lhůty kanceláře, Pošta, nabídky, tým |
| `/impersonation/accept` | Support handoff |
| `/payment-required` | licence |
| `/forbidden` | |

### Support app

| Route | Obrazovka |
| --- | --- |
| `/login` | e-mail / heslo |
| `/tenants` | seznam kanceláří |
| `/tenants/:id` | založení / Impersonar (důvod povinný) |
| `/forbidden` | účet není Support |

`www` v MVP stačí jednostránkový placeholder (není podmínka spuštění s design partnerem).

## 2. Inbox (`/inbox`)

Hlavní obrazovka po loginu.

Filtry: Vše / Dnes / Blíží se / Po termínu / Chybí dokument / Chybí údaje / Záloha / Zastaralý spis / Bez kanálu.  
Řádky z [deadline_engine.md](deadline_engine.md).

Bannery nad řádky (slot `inbox.feed`, ne rail): přepisy, `/kampane`, přeplatky. Pošta má `/posta` v railu.

Staré URL `/sezona-210` a `/po-notari` přesměrují na `/kampane`.

Každý řádek:

- jméno klienta, NIE short, adresa inmueble
- blok (Luz, Plusvalía, …)
- datum
- primární: **Abrir**
- sekundární: **Pedir al cliente** (otevře draft)

Prázdný stav: „No hay plazos para hoy. Puedes abrir un cliente o escanear un documento.“

## 3. Seznam klientů (`/clientes`)

- Vyhledávací pole nahoře = RPC z [search_spec.md](search_spec.md) (masky NIE)
- Tabulka: nombre, NIE, tel, # otevřených děr, poslední aktivita
- FAB / button **Nuevo cliente**
- Soft-deleted skrytí; owner toggle „Ver eliminados“

Nuevo cliente: jméno stačí. Po založení `/stoh` (přeskočit = deska). NIE, e-mail, tel, dirección, IBAN volitelné (IBAN povinný až u inkasa). Druhý kontakt + locale. Filtr aktivní / neaktivní.

## 4. Karta klienta (`/clientes/:id`)

Hub z náčrtu. Není to dlouhý formulář všech energií — energie žijí na inmueble.

**Horní pruh:** jméno, identifikátory, tel, e-mail, IBAN, jazyk. Badge děr.

**Akce:** Editar, Eliminar (confirm + soft), Restaurar (owner).

**Sloupce / sekce:**

1. Inmuebles (karty adresy → deska nemovitosti)
2. Expedientes abiertos (210, renta, NIE, policía, ayuntamiento, testament, compraventa)
3. Documentos del cliente (DNI, pasaporte)
4. Mensajes
5. Provisión součet přes otevřené spisy
6. Auditoría zkrácená (kdo otevřel / měnil) — owner

Tužka „nová koupě“: **Nuevo expediente compraventa** → vytvoří inmueble + šablonu bloků všech `off` kromě `cliente_snapshot`. Gestor zapíná bloky přepínačem = tužka.

## 5. Deska nemovitosti = dva tištěné listy

Route `/clientes/:id/carpeta` (ne `/inmuebles/:id`). Vizuálně **stejné pořadí jako papír**, ne dashboard widgety.

```
CLIENTE     (snapshot, odkaz na kartu)
ESCRITURA   notario / fecha / protocolo
AGUA        switch + pole + dokument
LUZ
GAZ
COMUNIDAD
SUMA
PLUSVALIA
SEGURO
PROVISION DE FONDOS Y FACTURA
ALARMA
EXTRAS      NIE    PODER
```

Každý blok na **deskách**:

- switch No aplica / Activo (tužka)
- stavový chip
- kryt (dodavatel / CUPS, počet papírů) — klik otevře šanon

Uvnitř `/carpeta/:bloque`: pole identity, dropzóna, stoh dokladů (faktury s obdobím a částkou). To zabíjí tiskárnu, aniž by deska byla SAP.

AI prefill zvýrazní žlutě změněná pole do Guardar / Descartar.

## 6. Expediente daně / NIE / úkony (`/expedientes/:id`)

Jednodušší než deska koupě: checklist + plazo + dokumenty jako sloty, klient a (u 210) nemovitost. Modelo 210 počítá IRNR (imputace / nájem / prodej) podle vyplněných polí; nepodává na AEAT. Policía / ayuntamiento / testament = stejný stroj (stav úkonu + cita + papír + úřad).

## 7. Zpráva

Z inboxu. Tělo šablony (gestor píše ES), úprava, **Enviar email** (překlad), **Copiar WhatsApp** (překlad), **Descartar**.  
Odeslání = člověk. Originál zůstane ve spisu. Compose: `/clientes/:id/mensaje`.

## 8. AI panel

Pravý dock (překryv na úzkém okně). Chat čte RPC (search, karta, dodávky, plazos, escritura, FTS). Extract je Edge `extract-document` → `ai_drafts`; Guardar je gestor. Draft výzvy je Edge `ai-draft-message` nebo compose.

## 9. Support

- Seznam tenantů, trial/active
- Onboard: název despacho, owner e-mail (invite edge)
- Licence toggle
- Impersonar (důvod povinný)
- Žádný seznam klientů kanceláře na Support home

## 10. Co na obrazovkách v MVP není

- Samostatné desky policie / magistrát / testament jako dva tištěné listy (tenký spis ano)
- Portál klienta
- WhatsApp API tlačítko odeslat (copy ano)
- Grafy MRR, účetní deník PGC, AEAT XML podání
- Mapa / geo
- Native share sheet mimo web download

## 11. Prázdné a chybové stavy

- 0 klientů: CTA sken DNI nebo Nuevo cliente
- Search 0: „Nadie con este NIE. Prueba la máscara Y123**6E.“
- Guardar konflikt: toast, nemazat draft AI
- Offline prohlížeč: banner „Sin conexión“, žádný fronta zápisů (online-only)

## 12. Pořadí stavby UI (až kód)

1. Auth + shell + Support tenant
2. Cliente CRUD + search
3. Inmueble deska bloků (papír)
4. Inbox + plazos
5. Mensajes draft/send/copy
6. AI extract/prefill/open
7. Provision tři čísla
8. Impuestos 210 s výpočtem IRNR; renta jako tenký spis
