# Seznam vývoje

Jak stavíme Sanfolio. Bible říká **co produkt je**. Tady je **pořadí práce**.

## Pravidlo

Stavíme jednu aplikaci pro **jednu kancelář i pro deset**. Gestorie Jarka je první tenant, na kterém to denně ověřujeme. Není strop a vývoj na ni nečeká.

Nabízet dalším kancelářím začneme, až je produkt dost dobrý. Do té doby:

1. Všechno, co nás napadne, se **ohodnotí** a **zařadí**.
2. Pracujeme **podle seznamu**, postupně.
3. Nový nápad nepřeskakuje frontu jen proto, že je čerstvý. Ani nečeká na „až budeme mít druhého klienta“.

Trvalé zákazy z [product_bible.md](product_bible.md) sem nepatří (hard delete, AI save/send, vlastní SIF, page-builder, …).

## Jak se řadí priorita

Defaultní pořadí vrstev (jako myUcto), dokud něco nedostane vyšší skóre:

1. Evidence a deska, kterou kancelář použije zítra ráno (klient, papír, termín, výzva, inbox).
2. Peníze kanceláře (záloha, kniha, SIF).
3. Podání na úřad z týchž dat.
4. Banka / inkaso.
5. Účetnictví (PGC, asientos).
6. Vertikály a kanály navíc (portál, WhatsApp API, extranjería, podpis).

Při novém nápadu stačí říct: *proč výš / níž než položka X*. Pak se seznam přepíše. Kód i dokumentace jdou ve stejném PR.

Každá položka ve frontě musí obstát u **jedné** kanceláře i u **deseti** (tenant, RLS, modul v `organization_modules`, i18n, žádný fork pro Jarku).

## V kódu (nefrontovat znovu)

- Složka, bloky, inbox, výzvy, přepis, Pošta, kniha faktur + Verifacti adapter
- Modelo 210 výpočet (ne podání AEAT)
- Kampaně 210 / po notáři, fronta přepisů, přeplatky vs. tarify, nabídky kanceláře
- Tenký spis policie / magistrát / závěť

## Fronta

Pořadí = aktuální priorita. Čísla se mění, když přijde lepší nápad.

| # | Položka | Poznámka |
| --- | --- | --- |
| 1 | Telematické podání AEAT (210, 211, 303, renta) | výpočet 210 na desce už je |
| 2 | Výpočet renta / IRPF a modelo 303 | checklist teď; číslo později |
| 3 | Párování banky a DPH 303 | z týchž dat, ne druhá app |
| 4 | Portál klienta | model zpráv (originál + překlad) už počítá |
| 5 | WhatsApp Business API | copy-to-WhatsApp teď |
| 6 | Digitální podpis | |
| 7 | Účetní deník PGC / asientos | defaultně za despacho |
| 8 | Extranjería (21 EX) / tráfico / laborál | jen modul, ne jádro |

Hotovou položku přesunout nahoru do „V kódu“. Novou položku vložit tam, kam patří podle priority — ne na konec „až někdy“.
