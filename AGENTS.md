# Gestoría OS — pravidla pro agenta

Čti a dodržuj `.cursor/rules/`. Jsou závazná, ne inspirace.

Stručně:

1. Složka klienta je zdroj pravdy. Zapnutá služba = blok.
2. Multi-tenant + RLS + soft-delete + append-only audit.
3. i18n JSON (cs, en, es, de, fr). Žádný hardcoded UI text.
4. Staff locale ≠ jazyk klienta. Zprávy: originál + překlad do `clientes.locale`.
5. Moduly + sloty. Žádný JSON page-builder.
6. Tenant si přizpůsobí lhůty v nastavení, ne forkem kódu.
7. AI: search / open / prefill / extract. Uživatel ukládá, maže, odesílá, podává.
8. Aditivní vývoj. Flutter web online-only. Jarka = první kancelář, ne strop.
9. Před kódem: `docs/ai_context/slovnik_modulu.md`. Po SQL: `docs/database_schema.md`.

Start: [README.md](README.md), [docs/README.md](docs/README.md).
