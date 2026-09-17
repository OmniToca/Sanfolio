# Ráno v kanceláři

Jedna strana pro staff. Není to help center. Texty v appce jsou z i18n (`cs` / `en` / `es` / `de` / `fr`).

## Rail (vlevo, na telefonu dole)

1. **Dnes** (`/inbox`) — termíny a díry. Pedir nachystá výzvu, Odeslat jste vy.
2. **Pošta** (`/posta`) — příchozí mail. Přiřadit klienta, uložit přílohu na desku.
3. **Klienti** — složka. Nový klient jde na stoh papírů, pak deska. CSV import na `/clientes/import` (duplicitní NIE přeskočí). Duplicity po CSV sloučí owner/gestor na `/clientes/sloucit`. Tisk desky = dva A4 z prohlížeče. Klik na blok otevře šanon.
4. **Faktury** — kniha Ventas / Compras, když má kancelář modul.
5. **Nastavení** — lhůty, Pošta ingest, tarify nabídek.

Asistent vpravo hledá a navrhuje. Guardar / Zahodit / Odeslat je vždy člověk.

## Bannery nad inboxem (ne nové ikony)

- **Přepisy** — návrh z PDF. Uložíte na desku, nebo zahodíte.
- **210, po notáři, IBI, expirace** — nepodané modelo 210, koupě kde zbývá plusvalía / dodávka, IBI/SUMA bez recibo (termín z Nastavení), a DNI / pas / poder / seguro v okně z nastavení. Hromadný Pedir nachystá drafty, Odeslat jste vy.
- **Bez kanálu** — karta bez e-mailu, telefonu nebo jazyka. Pedir smí použít druhý kontakt. Doplnění z kontaktu jen prázdná pole.
- **Platí víc než nabídka** — jen uložené faktury vs. tarify z Nastavení.
- **Kdo dluží** — záloha zbývá nula nebo míň. Prázdná složka bez pohybů tam není.
- **City dnes** — policie, magistrát, NIE a notář v jednom dni.

Pošta do inboxu jako banner nepatří — má vlastní položku.

## Výzva klientovi

Gestor píše španělsky. Do e-mailu jde překlad do jazyka karty. WhatsApp = kopie textu, ne automatické odeslání.

## Co systém neudělá sám

Nepodá 210 na AEAT. Nepřepne smlouvu u vody/světla. Neodešle výzvu. Nesmaže originál bez ownera a mimo legal hold.
