# MVP obrazovky

Cíl: paní přestane tisknout dva listy. Ráno inbox, přes den desky klienta = papír.

Všechny texty UI z i18n (`cs` default). Layout: rail vlevo (desktop) + top bar. Breakpoint ~720 px: bottom nav Inbox / Klienti / Nastavení.

## 1. Mapa rout

### Gestoría app

| Route | Obrazovka |
| --- | --- |
| `/login` | e-mail / heslo, zapomenuté heslo |
| `/reset-password` | nové heslo z odkazu v e-mailu |
| `/inbox` | denní smyčka |
| `/clientes` | seznam + nové (NIE není povinné) |
| `/clientes/:id` | deska klienta |
| `/clientes/:id/carpeta` | dva listy (tužka) |
| `/clientes/:id/inmuebles/:inmuebleId` | deska nemovitosti |
| `/expedientes/:id` | úkon (daně, NIE, poder) |
| `/mensajes/:id` | editor draftu; odeslat = překlad |
| `/settings` | lhůty kanceláře |
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

Filtry: Hoy / Vencido / Falta documento / Faltan datos / Provisión.  
Řádky z [deadline_engine.md](deadline_engine.md).

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

Nuevo cliente: jméno stačí. NIE, e-mail, tel, dirección, IBAN volitelné (IBAN povinný až u inkasa). Druhý kontakt + locale. Filtr aktivní / neaktivní.

## 4. Karta klienta (`/clientes/:id`)

Hub z náčrtu. Není to dlouhý formulář všech energií — energie žijí na inmueble.

**Horní pruh:** jméno, identifikátory, tel, e-mail, IBAN, jazyk. Badge děr.

**Akce:** Editar, Eliminar (confirm + soft), Restaurar (owner).

**Sloupce / sekce:**

1. Inmuebles (karty adresy → deska nemovitosti)
2. Expedientes abiertos (210, renta, NIE, poder, compraventa)
3. Documentos del cliente (DNI, pasaporte)
4. Mensajes
5. Provisión součet přes otevřené spisy
6. Auditoría zkrácená (kdo otevřel / měnil) — owner

Tužka „nová koupě“: **Nuevo expediente compraventa** → vytvoří inmueble + šablonu bloků všech `off` kromě `cliente_snapshot`. Gestor zapíná bloky přepínačem = tužka.

## 5. Deska nemovitosti = dva tištěné listy

Route inmueble. Vizuálně **stejné pořadí jako papír**, ne dashboard widgety.

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

Každý blok:

- switch No aplica / Activo (tužka)
- stavový chip (Faltan datos / Falta documento / En seguimiento / Hecho / Vencido)
- pole
- dropzóna dokumentu + seznam souborů
- pokud watching: datum plazo

To je obrazovka, která zabíjí tiskárnu. Desktop: 1 sloupec scroll. AI prefill zvýrazní žlutě změněná pole do Guardar / Descartar.

## 6. Expediente daně / NIE (`/expedientes/:id`)

Jednodušší než deska: checklist + plazo + dokumenty. Žádný kalkulátor 210.

## 7. Zpráva

Z inboxu nebo AI. Tělo šablony (gestor píše ES), úprava, **Enviar email** (překlad), **Copiar WhatsApp** (překlad), **Descartar**.  
Odeslání = člověk. Originál zůstane ve spisu.

## 8. AI panel

Pravý dock (překryv na úzkém okně). Umí hodit fotku/PDF. Turny v `ai_messages`. Eventy `navigate` a `prefill` viz [ai_contract.md](ai_contract.md).  
Na prefill desky zůstat na inmueble, neskákat pryč.

## 9. Support

- Seznam tenantů, trial/active
- Onboard: název despacho, owner e-mail (invite edge)
- Licence toggle
- Impersonar (důvod povinný)
- Žádný seznam klientů kanceláře na Support home

## 10. Co na obrazovkách v MVP není

- Samostatné desky policie / magistrát / testament (moduly zapnuté, UI později)
- Portál klienta
- WhatsApp API tlačítko odeslat (copy ano)
- Grafy MRR, účetní knihy, AEAT XML
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
8. Impuestos 210/renta jako tenké expedientes
