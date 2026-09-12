# Odpovědi — Gestorie Jarka

Zdroj: `/Users/petrsokol/Desktop/vyplnene_papiry.docx` (2026-09-11).  
Tohle je smlouva s kanceláří. Defaulty v kódu a SQL se jí musí rovnat.

## Kancelář

| | |
| --- | --- |
| Název | **Gestorie Jarka** (volitelné per tenant — jaký tenant, takový název) |
| Lidi u složek | 3, každý **vlastní jazyk UI** |
| Objem | ~500 aktivních + ~400 neaktivních klientů |
| Dva tištěné listy | zatím nevědí — doplnit později |

## Jazyky a zprávy

- Staff UI: **podle člověka** (`profiles.locale`), ne jedno pro kancelář.
- Odhad % jazyků klientů: nerelevantní — prostě CS/EN/DE/FR/ES.
- Gestor píše **španělsky**, přes překladač do jazyka klienta.
- Do e-mailu / WhatsApp jde **překlad** (jazyk klienta). Originál zůstane ve spisu a v klientské zóně vedle překladu.
- Kanály když chybí papír: **všechny** (WhatsApp, e-mail, telefon, osobně).
- Nachystat text a zkopírovat do WhatsApp: **ano**.

## Klient

- NIE **nemusí** být při založení. První úkol může být „vyřídit NIE“.
- Maskované NIE z úřadu: **často**.
- IBAN: v seznamu je, **povinný jen kvůli inkasu**.
- Druhý kontakt: občas, evidovat + **jazyk, kterým mluví**.
- Neaktivní klienti musí jít schovat, ne smazat (~400).

## Escritura / energie

- Kopie escritura: většinou.
- Referencia catastral: většinou.
- Lhůty od escritura (plusvalía, SUMA, IBI, seguro, alarm, poder): **všechno v nastavení kanceláře**, žádné zadrátované dny.
- Voda: smlouva, **číslo klienta na smlouvě**, faktury za vodu.
- Elektřina: **CUPS ano**, smlouva, faktury.
- Plyn: stejně jako elektřina.
- Comunidad: správce, účet, papír — ano.

## SUMA, honoráře, NIE, daně

- SUMA: **identifikační číslo**.
- Záloha: berou, stačí přijato / vyúčtováno / zbývá.
- NIE extras = **samostatný úkol**, ne jen pole na kartě.
- Poder: konec platnosti **individuálně** v nastavení (per poder / kancelář).
- Modelo 210: **čtvrtletně i ročně**. Papíry: všechny povinné ke zpracování 210. Výpočet daně **ne teď**, jen termín + checklist.
- Renta: v dotazníku prázdné — jen nastavitelné plazo.

## Moduly a skládání

Dělají **všechny** zaškrtnuté služby: koupě/energie, IBI/SUMA, 210, renta, NIE, poder, policie, magistrát, závěť/úmrtí.  
Pořadí bloků na desce si chtějí **přeskládat** (`tenant_settings.slot_order`).

## Bolest

Nejvíc času: **komunikace s klienty a dohledávání dokumentů**.  
Žádný termín nesmí utéct.
