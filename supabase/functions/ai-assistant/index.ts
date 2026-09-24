import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { embedTexts } from "../_shared/embed_chunks.ts";
import { corsHeaders } from "../_shared/cors.ts";

/**
 * Chat kanceláře. Whitelist tools, žádný save/delete/send.
 * Data jen z RPC v tenantovi volajícího.
 */

const tools = [
  {
    type: "function",
    function: {
      name: "search_clients",
      description:
        "Find clients by partial name/surname, NIE substring, phone, email, or address (home or finca). Pass only the name/NIE/address fragment in q, not the whole sentence. Returns top matches only (limit ~10) via indexed RPC — never load the whole tenant.",
      parameters: {
        type: "object",
        properties: { q: { type: "string" } },
        required: ["q"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "search_cliente_documentos",
      description:
        "List or filter papers on a client's pile (hromada/stoh): tipo, file name, ai_summary, body_text. Use for questions like 'jaké doklady má', 'je tam DNI', 'factura', 'scan e-mailu'. Empty q + cliente_id = list all. albums [] = still on pile.",
      parameters: {
        type: "object",
        properties: {
          cliente_id: { type: "string" },
          q: {
            type: "string",
            description: "Optional filter: DNI, factura, email, or free text",
          },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "get_cliente",
      description:
        "Read one client card, blocks, documents (albums [] = unfiled pile, inmueble/direccion = finca), and titular_inmuebles (folder sale price + share). Empty own desk is not 'no house'.",
      parameters: {
        type: "object",
        properties: { cliente_id: { type: "string" } },
        required: ["cliente_id"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "query_suministro",
      description: "Clients with energy/water company filled on the desk",
      parameters: {
        type: "object",
        properties: {
          company: { type: "string" },
          bloque_key: { type: "string", enum: ["luz", "agua", "gaz"] },
        },
        required: ["company"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "query_plazos_office",
      description: "Upcoming deadlines in the office (insurance, alarm, poder)",
      parameters: {
        type: "object",
        properties: {
          kind: { type: "string" },
          within_days: { type: "integer" },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "query_escritura",
      description:
        "Find the folder (carpeta owner) by notary, lawyer, cadastral, address, or a party on the deed (name/NIE in inmueble_titulares). Returns folder_cliente_id + sale_price. For a clause inside a 40-page PDF use search_document_text.",
      parameters: {
        type: "object",
        properties: {
          q: {
            type: "string",
            description: "Name, NIE, address, notary, lawyer, or cadastral",
          },
          notary: {
            type: "string",
            description: "Optional alias of q (legacy)",
          },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "search_document_text",
      description:
        "Search saved PDF transcripts by meaning or exact words (kauci = arras, IBI clause). Returns albums (empty = pile) and inmueble. Empty transcript is not proof the clause is missing. Use for human questions, not only legal terms.",
      parameters: {
        type: "object",
        properties: { q: { type: "string" } },
        required: ["q"],
      },
    },
  },
];

Deno.serve(async (req) => {
  const cors = corsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return json(405, { ok: false, error: "Method not allowed" });
  }
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json(401, { ok: false, error: "Missing Authorization" });
  }
  const userClient = createClient(supabaseUrl(), supabaseAnonKey(), {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) {
    return json(401, { ok: false, error: "Unauthorized" });
  }

  const body = await req.json() as {
    message?: unknown;
    locale?: unknown;
    cliente_id?: unknown;
    tenant_id?: unknown;
    focus_cliente_id?: unknown;
  };
  const message = typeof body.message === "string" ? body.message.trim() : "";
  const locale = typeof body.locale === "string" ? body.locale.trim() : "cs";
  const openClienteId = typeof body.cliente_id === "string"
    ? body.cliente_id.trim()
    : "";
  const focusClienteId = typeof body.focus_cliente_id === "string"
    ? body.focus_cliente_id.trim()
    : "";
  let tenantId = typeof body.tenant_id === "string" ? body.tenant_id.trim() : "";
  if (!message) return json(400, { ok: false, error: "message required" });

  if (tenantId) {
    const { data: allowed } = await userClient.rpc("can_access_tenant", {
      _tenant_id: tenantId,
    });
    if (allowed !== true) return json(403, { ok: false, error: "forbidden" });
  } else {
    const { data: mem } = await userClient
      .from("tenant_members")
      .select("tenant_id")
      .is("deleted_at", null)
      .limit(1)
      .maybeSingle();
    tenantId = `${mem?.tenant_id ?? ""}`;
    if (!tenantId) return json(403, { ok: false, error: "no tenant" });
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY")?.trim();
  if (!apiKey) return json(503, { ok: false, error: "LLM not configured" });

  const opens: Array<{
    cliente_id: string;
    label: string;
    carpeta: boolean;
    bloque_key?: string;
  }> = [];

  const intent = classifyIntent(message);
  const listAll = intent === "list";
  const pileQ = intent === "pile";
  const docPresenceQ = intent === "docPresence";
  const coOwnersQ = intent === "coOwners";
  const propertyQ = intent === "propertyCount";
  const identityQ = intent === "identity" || intent === "other";
  const followUp = looksLikeClientFollowUp(message);

  // „Tento klient“ = UUID z vlákna / otevřené karty — ne search přes celý tenant.
  const sessionCliente = openClienteId ||
    (followUp ? focusClienteId : "") ||
    "";

  // Otevřená / focus karta = context hned (1× get_cliente), ať model nehledá.
  // Bez body_excerpt wall — jinak LLM/fallback dumpuje stejný stoh.
  let openSnap: unknown = null;
  if (sessionCliente) {
    const snap = await runTool(
      userClient,
      tenantId,
      "get_cliente",
      { cliente_id: sessionCliente },
      opens,
      apiKey,
    );
    if (
      snap &&
      typeof snap === "object" &&
      !("error" in (snap as Record<string, unknown>))
    ) {
      openSnap = slimClienteSnap(
        snap,
        pileQ || docPresenceQ ? "pile" : "card",
      );
    }
  }

  // Search jen když není follow-up UUID. Top N přes RPC (index/ILIKE/trgm), ne O(n).
  const preHits = listAll
    ? await listClientHits(userClient, 20)
    : (followUp && sessionCliente
      ? []
      : await searchClientHits(userClient, message, 10));
  for (const hit of preHits) {
    if (opens.some((o) => o.cliente_id === hit.cliente_id && !o.bloque_key)) {
      continue;
    }
    opens.push({
      cliente_id: hit.cliente_id,
      label: hit.nombre || hit.cliente_id,
      carpeta: true,
    });
  }

  const focusCliente = sessionCliente || preHits[0]?.cliente_id || "";

  // Hromada / doc-presence: vždy scoped na konkrétní cliente_id po resoluci.
  let preDocs: unknown = null;
  if ((pileQ || docPresenceQ) && focusCliente) {
    const docQ = looksLikeListPileDocs(message) && !docPresenceQ
      ? ""
      : message;
    const rawDocs = await runTool(
      userClient,
      tenantId,
      "search_cliente_documentos",
      { cliente_id: focusCliente, q: docQ },
      opens,
      apiKey,
    );
    preDocs = slimPileDocs(rawDocs);
  }

  let preCoOwners: unknown = null;
  if (coOwnersQ && focusCliente) {
    preCoOwners = await loadFolderCoOwners(userClient, focusCliente);
  }

  let preProperties: unknown = null;
  if (propertyQ && focusCliente) {
    preProperties = await loadFolderProperties(userClient, focusCliente);
  }

  // Deterministické krátké odpovědi — bez LLM dump identity karty.
  const det = deterministicReply({
    intent,
    locale,
    focusCliente,
    followUp,
    preHits,
    preDocs,
    preCoOwners,
    preProperties,
    openSnap,
  });
  if (det) {
    const admin = createClient(supabaseUrl(), serviceRoleKey(), {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    await admin.from("audit_logs").insert({
      tenant_id: tenantId,
      actor_id: userData.user.id,
      action: "ai.tool",
      entity_table: "ai_conversations",
      after: { tool: "ai_assistant", mode: "deterministic", intent },
    });
    return json(200, { ok: true, text: det.text, opens: det.opens.length ? det.opens : opens });
  }

  const clienteId = sessionCliente;

  const messages: Array<Record<string, unknown>> = [
    {
      role: "system",
      content:
        `Jsi asistent španělské gestoría. Odpovídej jazykem ${locale}. ` +
        "Data čteš jen tools a snapshoty níže. Nevymýšlíš NIE ani doložky. Neříkej, že jsi uložil. " +
        "Odpovídej KRÁTCE podle záměru otázky — nevypisuj celý seznam dokladů, pokud se neptají na hromadu/doklady. " +
        "Identita / jméno / NIE / telefon = 1–3 řádky (jméno + NIE), ne dump PDF. " +
        "Spoluvlastníci / titulares / co-owners = použij co_owners níže (jiné osoby na finca složky), ne documentos. " +
        "Nemovitost / finca / kolik = properties níže (počet + adresy), ne výpis faktur. " +
        "Kupní smlouva / escritura / DNI / poder = ano/ne + které papíry z hromady (preDocs), ne identity karta. " +
        "Prázdné pole na desce ≠ neexistuje smlouva — řekni, že to na desce není vyplněné. " +
        "Částka na desce dodávky není součet faktur. Součet je invoice_glance / fields.amount na dokumentech (kladné; dobropis ne). " +
        "Office otázky (dodavatel, seguro, notář, právník, catastral, strana ve smlouvě) = query_* tools. " +
        "Věta / doložka ve smlouvě = search_document_text (přepis; rozumí i lidské otázce, nemusí to být přesný právní termín). " +
        "Hromada / stoh / jaké doklady / je tam DNI / factura / e-mail = search_cliente_documentos (tipo, název, summary, body). Max ~8 položek ve výpisu. " +
        "Když body_text chybí, neříkej že ve smlouvě věta není — přepis ještě není uložený. " +
        "get_cliente.titular_inmuebles: tato karta je titular na finca složky folder_cliente_id (ona jinde). " +
        "co_owners: OSTATNÍ titulares na finca TÉTO složky (Jaroslava/Darran u Renaty). " +
        "get_cliente.identifiers: NIE/DNI/NIF karty. get_cliente.documentos jen když se ptají na papíry. " +
        "search_document_text / search_cliente_documentos / get_cliente.documentos: albums [] = hromada; jinak template_key alb. inmueble_id / direccion = finca. " +
        "Cena domu = sale_price celé listiny; podíl = share_percent. Prázdné documentos[] na kartě titulare ≠ dům nemáme. " +
        "Open = deska složky folder_cliente_id (/carpeta), ne šanon escritura (může být vypnutý) a ne prázdná karta spoluvlastníka. " +
        "search_clients: do q dej jen jméno, část NIE nebo adresu (ne celou větu). Top 10 hitů — ne načítat všechny klienty. " +
        "Seznam klientů = max 20 jmen z hits (list), ne dump 100 karet. " +
        "Když níže jsou hits s jménem/NIE/adresou, použij je — neříkej že nikoho nenašel. " +
        (clienteId
          ? `Focus klient (UUID): ${clienteId}. Na „tento/ta klient(ka)“ ber snapshot níže — nehledej znovu. `
          : focusClienteId
          ? `Poslední klient ve vlákně: ${focusClienteId}. Follow-up bez jména = tento UUID. `
          : "") +
        (identityQ && !pileQ && !docPresenceQ
          ? "Tato otázka NENÍ výpis dokladů — odpověz stručně. "
          : ""),
    },
    ...(openSnap
      ? [{
        role: "system" as const,
        content: `Snapshot focus karty (read-only): ${JSON.stringify(openSnap)}`,
      }]
      : []),
    ...(preHits.length > 0
      ? [{
        role: "system" as const,
        content:
          `Hits z RPC search/list (read-only, max ${listAll ? 20 : 10}): ${
            JSON.stringify(preHits)
          }. ` +
          (identityQ && !pileQ
            ? "Stačí jméno (+ NIE z get_cliente pokud potřeba); nevypisuj documentos."
            : "Odpověz podle nich; get_cliente pro detail."),
      }]
      : []),
    ...(preDocs
      ? [{
        role: "system" as const,
        content:
          `Doklady (scoped cliente_id, read-only, max 8): ${JSON.stringify(preDocs)}. ` +
          (docPresenceQ
            ? "Odpověz ano/ne + které papíry; ne identity kartu."
            : "Odpověz podle nich; albums [] = ještě na hromadě."),
      }]
      : []),
    ...(preCoOwners
      ? [{
        role: "system" as const,
        content:
          `Spoluvlastníci / titulares na finca složky (read-only): ${JSON.stringify(preCoOwners)}. ` +
          "Vypiš jména (a NIE/adresu); ne dump dokladů.",
      }]
      : []),
    ...(preProperties
      ? [{
        role: "system" as const,
        content:
          `Nemovitosti složky (read-only, scoped): ${JSON.stringify(preProperties)}. ` +
          "Odpověz počtem a adresami; ne dump faktur/PDF.",
      }]
      : []),
    { role: "user", content: message },
  ];

  let text = "";
  for (let i = 0; i < 4; i++) {
    const res = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        temperature: 0,
        messages,
        tools,
        tool_choice: "auto",
      }),
    });
    if (!res.ok) {
      return json(502, { ok: false, error: "LLM failed" });
    }
    const data = await res.json() as {
      choices?: Array<{
        message?: {
          content?: string;
          tool_calls?: Array<{
            id: string;
            function: { name: string; arguments: string };
          }>;
        };
      }>;
    };
    const msg = data.choices?.[0]?.message;
    if (!msg) break;
    const calls = msg.tool_calls ?? [];
    if (calls.length === 0) {
      text = (msg.content ?? "").trim();
      break;
    }
    messages.push(msg);
    for (const call of calls) {
      const args = parseArgs(call.function.arguments);
      const result = await runTool(
        userClient,
        tenantId,
        call.function.name,
        args,
        opens,
        apiKey,
      );
      messages.push({
        role: "tool",
        tool_call_id: call.id,
        content: JSON.stringify(result),
      });
    }
  }

  if (!text) {
    return json(200, { ok: false, error: "empty" });
  }

  const admin = createClient(supabaseUrl(), serviceRoleKey(), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  await admin.from("audit_logs").insert({
    tenant_id: tenantId,
    actor_id: userData.user.id,
    action: "ai.tool",
    entity_table: "ai_conversations",
    after: { tool: "ai_assistant" },
  });

  return json(200, { ok: true, text, opens });
});

function parseArgs(raw: string): Record<string, unknown> {
  try {
    const v = JSON.parse(raw);
    return v && typeof v === "object" ? v as Record<string, unknown> : {};
  } catch {
    return {};
  }
}

async function runTool(
  client: SupabaseClient,
  tenantId: string,
  name: string,
  args: Record<string, unknown>,
  opens: Array<{
    cliente_id: string;
    label: string;
    carpeta: boolean;
    bloque_key?: string;
  }>,
  apiKey: string,
): Promise<unknown> {
  switch (name) {
    case "search_clients": {
      const q = str(args.q);
      const hits = await searchClientHits(client, q, 10);
      return hits;
    }
    case "search_cliente_documentos": {
      const id = str(args.cliente_id);
      const q = str(args.q);
      const { data, error } = await client.rpc("search_cliente_documentos", {
        p_cliente_id: id || null,
        p_q: q,
        p_limit: 8,
      });
      if (error) return { error: error.message };
      const slim = slimPileDocs(data);
      collectOpens(slim, opens);
      return slim;
    }
    case "get_cliente": {
      const id = str(args.cliente_id);
      const { data, error } = await client.rpc("ai_get_cliente", {
        p_cliente_id: id,
      });
      if (error) return { error: error.message };
      collectClienteOpens(data, opens);
      // Tool volání z LLM: vždy zkrácený snap (ne 11× body_excerpt).
      return slimClienteSnap(attachInvoiceGlance(data), "pile");
    }
    case "query_suministro": {
      const { data, error } = await client.rpc("query_suministro", {
        p_tenant_id: tenantId,
        p_company: str(args.company),
        p_bloque_key: str(args.bloque_key) || "luz",
      });
      if (error) return { error: error.message };
      collectOpens(data, opens);
      return data;
    }
    case "query_plazos_office": {
      const { data, error } = await client.rpc("query_plazos_office", {
        p_tenant_id: tenantId,
        p_kind: str(args.kind) || "seguro_renovacion",
        p_within_days: Number(args.within_days) || 90,
      });
      if (error) return { error: error.message };
      collectOpens(data, opens);
      return data;
    }
    case "query_escritura": {
      const { data, error } = await client.rpc("query_escritura", {
        p_tenant_id: tenantId,
        p_notary: str(args.q) || str(args.notary),
      });
      if (error) return { error: error.message };
      collectOpens(data, opens);
      return data;
    }
    case "search_document_text": {
      const q = str(args.q);
      return await searchDocumentHybrid(client, tenantId, q, apiKey, opens);
    }
    default:
      return { error: "unknown_tool" };
  }
}

function collectClienteOpens(
  data: unknown,
  opens: Array<{
    cliente_id: string;
    label: string;
    carpeta: boolean;
    bloque_key?: string;
  }>,
) {
  if (!data || typeof data !== "object") return;
  const snap = data as {
    cliente?: { id?: string; nombre?: string };
    titular_inmuebles?: Array<{
      folder_cliente_id?: string;
      folder_nombre?: string;
      folder_has_carpeta?: boolean;
      direccion?: string;
    }>;
  };
  const titulares = Array.isArray(snap.titular_inmuebles)
    ? snap.titular_inmuebles
    : [];
  let openedFolder = false;
  for (const t of titulares) {
    const folderId = `${t.folder_cliente_id ?? ""}`;
    if (!folderId) continue;
    if (opens.some((o) => o.cliente_id === folderId && !o.bloque_key)) {
      openedFolder = true;
      continue;
    }
    const name = `${t.folder_nombre ?? folderId}`.trim();
    const address = `${t.direccion ?? ""}`.trim();
    opens.push({
      cliente_id: folderId,
      label: address ? `${name} · ${address}` : name,
      carpeta: true,
    });
    openedFolder = true;
  }
  if (openedFolder) return;
  collectOpens(data, opens);
}

function collectOpens(
  data: unknown,
  opens: Array<{
    cliente_id: string;
    label: string;
    carpeta: boolean;
    bloque_key?: string;
  }>,
) {
  const items = data && typeof data === "object" && "items" in data
    ? (data as { items: unknown }).items
    : data && typeof data === "object" && "cliente" in data
    ? [(data as { cliente: { id?: string; nombre?: string } }).cliente]
    : null;
  if (!Array.isArray(items)) return;
  for (const raw of items) {
    if (!raw || typeof raw !== "object") continue;
    const row = raw as {
      cliente_id?: string;
      folder_cliente_id?: string;
      id?: string;
      nombre?: string;
      original_name?: string;
      bloque_key?: string;
    };
    const id = `${row.folder_cliente_id ?? row.cliente_id ?? row.id ?? ""}`;
    const fileName = `${row.original_name ?? ""}`.trim();
    // Escritura bez souboru = deska. Šanon může být Nesledujeme (dům je na titularech).
    let bloque = `${row.bloque_key ?? ""}`.trim();
    if (bloque === "escritura" && !fileName) bloque = "";
    if (!id || opens.some((o) => o.cliente_id === id && (o.bloque_key ?? "") === bloque)) {
      continue;
    }
    const label = fileName || `${row.nombre ?? id}`;
    opens.push({
      cliente_id: id,
      label,
      carpeta: true,
      ...(bloque ? { bloque_key: bloque } : {}),
    });
  }
}

function attachInvoiceGlance(data: unknown): unknown {
  if (!data || typeof data !== "object") return data;
  const docs = (data as { documentos?: unknown }).documentos;
  if (!Array.isArray(docs)) return data;
  let paidCents = 0;
  let count = 0;
  const items: Array<Record<string, string | number>> = [];
  for (const raw of docs) {
    if (!raw || typeof raw !== "object") continue;
    const row = raw as {
      tipo?: string;
      extracted?: Record<string, unknown>;
    };
    const tipo = `${row.tipo ?? ""}`;
    if (!tipo.startsWith("factura") && !tipo.startsWith("recibo")) continue;
    count += 1;
    const extracted = row.extracted ?? {};
    const cents = parseAmountCents(`${extracted["fields.amount"] ?? ""}`);
    if (cents > 0) paidCents += cents;
    const from = `${extracted["fields.periodFrom"] ?? ""}`.trim();
    const to = `${extracted["fields.periodTo"] ?? ""}`.trim();
    items.push({
      tipo,
      period: [from, to].filter(Boolean).join(" – "),
      amount_cents: cents,
    });
  }
  return {
    ...(data as Record<string, unknown>),
    invoice_glance: {
      count,
      paid_euros: (paidCents / 100).toFixed(2).replace(".", ","),
      items,
    },
  };
}

function parseAmountCents(raw: string): number {
  const t0 = raw.trim();
  if (!t0) return 0;
  if (/^-?\d+$/.test(t0)) return Number.parseInt(t0, 10);
  let t = t0.replace(/\s/g, "");
  const lastComma = t.lastIndexOf(",");
  const lastDot = t.lastIndexOf(".");
  if (lastComma > lastDot) t = t.replace(/\./g, "").replace(",", ".");
  else t = t.replace(/,/g, "");
  const n = Number.parseFloat(t);
  if (!Number.isFinite(n)) return 0;
  return Math.round(n * 100);
}

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

type ClientHit = {
  cliente_id: string;
  nombre: string;
  score: number;
  matched_via?: string;
};

const SEARCH_STOP = new Set([
  "jak", "se", "jsem", "jsme", "mam", "mame", "máme", "klient", "klienta",
  "klienti", "klienty", "klientu", "klientů", "nasi", "naši", "nase", "naše",
  "jmenuji", "jmenuje", "jmenují", "jmeno", "jméno", "jménem", "nie", "dni",
  "nif", "kolik", "kde", "kdo", "co", "pro", "dal", "dál", "jeho", "její",
  "dokumentu", "dokumentů", "dokumenty", "dokument", "doklady", "hromade",
  "hromadě", "hromada", "stoh", "papír", "papir", "scan", "sken", "email",
  "mail", "posta", "pošta", "factura", "faktura", "adresa", "bydliště",
  "bydliste", "finca", "ma", "má", "tam", "je", "jake", "jaké", "ukaz", "ukaž",
  "the", "and", "or", "of", "for", "with", "our", "my", "client", "clients",
  "name", "who", "what", "how", "have", "has", "is", "are", "we", "you",
  "document", "documents", "pile", "invoice", "address", "show", "list",
  "el", "la", "los", "las", "un", "una", "de", "del", "cliente", "clientes",
  "nombre", "documento", "documentos", "factura", "correo", "direccion",
  "der", "die", "das", "und", "kunde", "kunden", "dokument", "rechnung",
  "le", "les", "des", "notre", "s", "a", "i", "u", "v", "z", "na", "do", "od",
  "po", "za",
]);

function searchQueryContent(raw: string): string {
  return raw
    .trim()
    .split(/\s+/)
    .map((t) => t.replace(/^[.,;:!?„“"'()[\]{}]+|[.,;:!?„“"'()[\]{}]+$/g, ""))
    .filter((t) => t.length >= 2 && !SEARCH_STOP.has(t.toLowerCase()))
    .join(" ");
}

function searchQueryIdTokens(raw: string): string[] {
  const out = new Set<string>();
  for (const m of raw.matchAll(/[A-Za-z0-9*]+/g)) {
    const tok = m[0].toUpperCase();
    if (tok.length < 4) continue;
    if (
      /^[XYZ][0-9*]{7}[A-Z]$/.test(tok) ||
      /^[0-9*]{8}[A-Z]$/.test(tok) ||
      /^[XYZ][0-9*]{3,}$/.test(tok) ||
      /^[0-9*]{5,}$/.test(tok)
    ) {
      out.add(tok);
    }
  }
  return [...out];
}

function searchNameStem(raw: string): string {
  const n = raw.toLowerCase().normalize("NFD").replace(/\p{M}/gu, "");
  if (n.length < 4) return n;
  const stemmed = n.replace(
    /(ovou|ovi|ych|ami|ach|ech|ove|ovy|ova|ovu|emu|oum|em|ou|um|y|u|e|a|i)$/,
    "",
  );
  return stemmed.length >= 3 ? stemmed : n;
}

function searchClientQueries(raw: string): string[] {
  const q = raw.trim();
  if (!q) return [];
  const out: string[] = [];
  const add = (s: string) => {
    const t = s.trim();
    if (t.length < 2) return;
    if (out.some((e) => e.toLowerCase() === t.toLowerCase())) return;
    out.push(t);
  };
  for (const id of searchQueryIdTokens(q)) add(id);
  const content = searchQueryContent(q);
  if (content) {
    add(content);
    for (const tok of content.split(/\s+/)) {
      if (tok.length < 2) continue;
      add(tok);
      const stem = searchNameStem(tok);
      if (stem !== tok.toLowerCase() && stem.length >= 3) add(stem);
    }
  }
  if (!q.includes(" ") && !content) add(q);
  if (out.length === 0) add(q);
  return out;
}

function looksLikeListClients(raw: string): boolean {
  const n = raw.toLowerCase();
  const asks = /klient|client|kunde|cliente/.test(n);
  if (!asks) return false;
  if (searchQueryContent(raw) || searchQueryIdTokens(raw).length) return false;
  return /jmen|naši|nasi|nase|naše|seznam|všechn|vsechn|list|all |our |tenemos|nuestros|haben wir|avons|systém|system/
    .test(n);
}

function looksLikeClientFollowUp(raw: string): boolean {
  const n = raw.toLowerCase().normalize("NFD").replace(/\p{M}/gu, "");
  if (/\b(tento|tato|ten|ta|tohoto|teto|te|toho)\s+klient/.test(n)) return true;
  if (/\b(u\s+n[ei]|u\s+nich|this\s+client|este\s+cliente|dieser\s+kunde|ce\s+client)\b/.test(n)) {
    return true;
  }
  return /ta klientka|te klientky|tohoto klienta/.test(n);
}

function looksLikeCoOwners(raw: string): boolean {
  const n = raw.toLowerCase().normalize("NFD").replace(/\p{M}/gu, "");
  return /spoluvlast|titular|cotitular|co-?owner|coowner|copropriet|miteigent|compropriet|joint owner|otros duenos/
    .test(n);
}

function looksLikePropertyCount(raw: string): boolean {
  const n = raw.toLowerCase().normalize("NFD").replace(/\p{M}/gu, "");
  const hasProp =
    /nemovit|finca|inmueble|propert|immobilie|vivienda|propied|\bbyt\b|\bbyty\b|\bdum\b|\bdomy\b/
      .test(n);
  if (!hasProp) return false;
  // „má nějakou nemovitost“ i bez „kolik“
  return /kolik|pocet|how many|cuant|wieviel|combien|jake ma|ma nejak|nejakou|nejaky|nejake|any |alguna|ktere|which|donde|kde ma|\bma\b|\btiene\b|\bhave\b|\bhas\b|mame|mate/
    .test(n);
}

function looksLikeDocPresence(raw: string): boolean {
  if (looksLikeCoOwners(raw) || looksLikePropertyCount(raw)) return false;
  const n = raw.toLowerCase().normalize("NFD").replace(/\p{M}/gu, "");
  // NIE fragment = identita, ne papír DNI
  if (
    searchQueryIdTokens(raw).length > 0 &&
    !/\b(dni|pasport|pasaporte|passport|obcans|doklad|dokument|escritur|kupni|compraventa|smlouv|poder|factura|faktur|iban)\b/
      .test(n)
  ) {
    return false;
  }
  const parts = searchDocQueryParts(raw);
  if (parts.length === 0) return false;
  if (looksLikeListPileDocsLoose(raw)) return false;
  return /mame|mate|\bma\b|je tam|existuje|\bu\b|have|has |tiene|tenemos|hay |got /
    .test(n);
}

function looksLikePileDocs(raw: string): boolean {
  if (
    looksLikeCoOwners(raw) ||
    looksLikePropertyCount(raw) ||
    looksLikeDocPresence(raw)
  ) {
    return false;
  }
  const n = raw.toLowerCase().normalize("NFD").replace(/\p{M}/gu, "");
  // „podle dokumentů“ u jiné otázky ≠ výpis hromady.
  if (
    /podle/.test(n) &&
    /dokument|document/.test(n) &&
    searchDocQueryParts(raw).length === 0 &&
    !/hromad|stoh|doklad/.test(n)
  ) {
    return false;
  }
  return /hromad|stoh|dokument|doklad|pap[ií]r|scan|sken|dni|pasport|pasaporte|factura|faktur|invoice|email|e-mail|correo|pošta|posta|\bmail\b|escritur|listin|poder|iban|pile|document|rechnung|je tam|má na|ma na|má v|ma v|kupni|compraventa|smlouv/
    .test(n);
}

function looksLikeIdentity(raw: string): boolean {
  if (
    looksLikeListClients(raw) ||
    looksLikeCoOwners(raw) ||
    looksLikePropertyCount(raw) ||
    looksLikeDocPresence(raw) ||
    looksLikePileDocs(raw)
  ) {
    return false;
  }
  const n = raw.toLowerCase().normalize("NFD").replace(/\p{M}/gu, "");
  if (/jmen|nie|dni|nif|telefon|\btel\b|email|e-mail|correo|phone|llam|who is|kdo je/.test(n)) {
    return true;
  }
  const ids = searchQueryIdTokens(raw);
  const content = searchQueryContent(raw);
  const toks = content.split(/\s+/).filter(Boolean);
  if (ids.length && toks.length <= 3) return true;
  if (toks.length > 0 && toks.length <= 3 && searchDocQueryParts(raw).length === 0) {
    return !/hromad|stoh|doklad|faktura|factura/.test(n);
  }
  return false;
}

type NlIntent =
  | "list"
  | "coOwners"
  | "propertyCount"
  | "docPresence"
  | "pile"
  | "identity"
  | "other";

function classifyIntent(raw: string): NlIntent {
  if (looksLikeListClients(raw)) return "list";
  if (looksLikeCoOwners(raw)) return "coOwners";
  if (looksLikePropertyCount(raw)) return "propertyCount";
  if (looksLikeDocPresence(raw)) return "docPresence";
  if (looksLikePileDocs(raw)) return "pile";
  if (looksLikeIdentity(raw)) return "identity";
  return "other";
}

/** Krátká odpověď z prefetch — bez LLM identity dump. */
function deterministicReply(args: {
  intent: NlIntent;
  locale: string;
  focusCliente: string;
  followUp: boolean;
  preHits: ClientHit[];
  preDocs: unknown;
  preCoOwners: unknown;
  preProperties: unknown;
  openSnap: unknown;
}): { text: string; opens: Array<{ cliente_id: string; label: string; carpeta: boolean }> } | null {
  const { intent, focusCliente, followUp, preDocs, preCoOwners, preProperties, openSnap } =
    args;
  const nameFromSnap = (() => {
    if (!openSnap || typeof openSnap !== "object") return "";
    const c = (openSnap as { cliente?: { nombre?: string } }).cliente;
    return `${c?.nombre ?? ""}`.trim();
  })();

  if (
    (intent === "propertyCount" || intent === "docPresence" || intent === "coOwners") &&
    !focusCliente
  ) {
    if (followUp) {
      return {
        text: args.locale.startsWith("cs")
          ? "Nejdřív uveďte klienta (jméno / NIE), nebo se zeptejte po nalezení karty — „tento klient“ drží jen v tomto vlákně."
          : "Name a client first (or ask after opening a card). “This client” only works in the same thread.",
        opens: [],
      };
    }
    return null;
  }

  if (intent === "propertyCount" && focusCliente && preProperties) {
    const p = preProperties as {
      count?: number;
      addresses?: string[];
      cliente_id?: string;
    };
    const count = Number(p.count) || 0;
    const addrs = Array.isArray(p.addresses) ? p.addresses : [];
    const name = nameFromSnap || "—";
    const lines = [
      args.locale.startsWith("cs")
        ? `Nemovitosti — ${name} (${count})`
        : `Properties — ${name} (${count})`,
    ];
    if (count === 0 && addrs.length === 0) {
      lines.push(
        args.locale.startsWith("cs")
          ? "Na složce zatím není žádná finca."
          : "This folder has no finca yet.",
      );
    } else {
      for (const a of addrs.slice(0, 8)) lines.push(a);
    }
    return {
      text: lines.join("\n"),
      opens: [{ cliente_id: focusCliente, label: name, carpeta: true }],
    };
  }

  if (intent === "coOwners" && focusCliente && preCoOwners) {
    const c = preCoOwners as {
      items?: Array<{ nombre?: string; nie?: string; direccion?: string; share_percent?: number }>;
    };
    const items = Array.isArray(c.items) ? c.items : [];
    const name = nameFromSnap || "—";
    if (items.length === 0) {
      return {
        text: args.locale.startsWith("cs")
          ? `U ${name} nemám v titulares jiné spoluvlastníky.`
          : `No other co-owners in titulares for ${name}.`,
        opens: [{ cliente_id: focusCliente, label: name, carpeta: true }],
      };
    }
    const lines = [
      args.locale.startsWith("cs")
        ? `Spoluvlastníci — ${name} (${items.length})`
        : `Co-owners — ${name} (${items.length})`,
    ];
    for (const t of items.slice(0, 12)) {
      const bits = [
        `${t.nombre ?? ""}`.trim(),
        t.nie ? `NIE: ${t.nie}` : "",
        `${t.direccion ?? ""}`.trim(),
        t.share_percent != null ? `${t.share_percent} %` : "",
      ].filter(Boolean);
      lines.push(bits.join(" · "));
    }
    return {
      text: lines.join("\n"),
      opens: [{ cliente_id: focusCliente, label: name, carpeta: true }],
    };
  }

  if (intent === "docPresence" && focusCliente && preDocs) {
    const d = preDocs as {
      total?: number;
      items?: Array<{
        tipo?: string;
        original_name?: string;
        ai_summary?: string;
        albums?: unknown;
      }>;
      cliente?: { nombre?: string };
    };
    const name = `${d.cliente?.nombre ?? nameFromSnap}`.trim() || "—";
    const items = Array.isArray(d.items) ? d.items : [];
    const total = Number(d.total) || items.length;
    if (items.length === 0) {
      return {
        text: args.locale.startsWith("cs")
          ? `Ne — u ${name} teď takový papír na hromadě / ve spisu nevidím.`
          : `No — I do not see that paper on the pile / in the file for ${name}.`,
        opens: [{ cliente_id: focusCliente, label: name, carpeta: true }],
      };
    }
    const lines = [
      args.locale.startsWith("cs")
        ? `Ano — u ${name} je ${total} odpovídající papír(ů):`
        : `Yes — ${name} has ${total} matching paper(s):`,
    ];
    for (const doc of items.slice(0, 8)) {
      const bits = [
        `${doc.tipo ?? ""}`.trim(),
        `${doc.original_name ?? ""}`.trim(),
        `${doc.ai_summary ?? ""}`.trim(),
      ].filter(Boolean);
      lines.push(bits.join(" · "));
    }
    return {
      text: lines.join("\n"),
      opens: [{ cliente_id: focusCliente, label: name, carpeta: true }],
    };
  }

  if (intent === "list" && args.preHits.length > 0) {
    const lines = [
      args.locale.startsWith("cs") ? "Nalezení klienti" : "Matching clients",
    ];
    for (const h of args.preHits.slice(0, 20)) {
      lines.push(h.nombre || h.cliente_id);
    }
    if (args.preHits.length >= 20) {
      lines.push(
        args.locale.startsWith("cs")
          ? "…ukazuji max. 20 — upřesněte jménem / NIE."
          : "…showing max 20 — narrow by name / NIE.",
      );
    }
    return {
      text: lines.join("\n"),
      opens: args.preHits.slice(0, 20).map((h) => ({
        cliente_id: h.cliente_id,
        label: h.nombre || h.cliente_id,
        carpeta: true,
      })),
    };
  }

  return null;
}

// Snapshot bez wall body_excerpt — card mode vyhodí documentos, pile zkrátí.
function slimClienteSnap(snap: unknown, mode: "card" | "pile"): unknown {
  if (!snap || typeof snap !== "object") return snap;
  const s = { ...(snap as Record<string, unknown>) };
  if (mode === "card") {
    delete s.documentos;
    delete s.holes;
    if (s.invoice_glance && typeof s.invoice_glance === "object") {
      const g = s.invoice_glance as Record<string, unknown>;
      s.invoice_glance = { count: g.count, paid_euros: g.paid_euros };
    }
    return s;
  }
  const docs = Array.isArray(s.documentos) ? s.documentos : [];
  s.documentos = docs.slice(0, 8).map((raw) => {
    if (!raw || typeof raw !== "object") return raw;
    const d = { ...(raw as Record<string, unknown>) };
    const excerpt = `${d.body_excerpt ?? ""}`;
    if (excerpt.length > 280) d.body_excerpt = `${excerpt.slice(0, 280)}…`;
    return d;
  });
  return s;
}

function slimPileDocs(data: unknown): unknown {
  if (!data || typeof data !== "object") return data;
  const d = { ...(data as Record<string, unknown>) };
  const items = Array.isArray(d.items) ? d.items : [];
  d.items = items.slice(0, 8).map((raw) => {
    if (!raw || typeof raw !== "object") return raw;
    const row = { ...(raw as Record<string, unknown>) };
    const excerpt = `${row.body_excerpt ?? ""}`;
    if (excerpt.length > 200) row.body_excerpt = `${excerpt.slice(0, 200)}…`;
    return row;
  });
  return d;
}

async function loadFolderCoOwners(
  client: SupabaseClient,
  folderClienteId: string,
): Promise<unknown> {
  const { data: inms, error: e1 } = await client
    .from("inmuebles")
    .select("id, direccion")
    .eq("cliente_id", folderClienteId)
    .is("deleted_at", null);
  if (e1 || !Array.isArray(inms) || inms.length === 0) {
    return { cliente_id: folderClienteId, items: [], total: 0 };
  }
  const addr = new Map<string, string>();
  const ids: string[] = [];
  for (const raw of inms) {
    const row = raw as { id?: string; direccion?: string };
    const id = `${row.id ?? ""}`;
    if (!id) continue;
    ids.push(id);
    const d = `${row.direccion ?? ""}`.trim();
    if (d) addr.set(id, d);
  }
  const { data: tits, error: e2 } = await client
    .from("inmueble_titulares")
    .select("nombre, nie_raw, cliente_id, lado, cuota_bps, inmueble_id")
    .in("inmueble_id", ids)
    .is("deleted_at", null);
  if (e2 || !Array.isArray(tits)) {
    return { cliente_id: folderClienteId, items: [], total: 0 };
  }
  const items: Array<Record<string, unknown>> = [];
  for (const raw of tits) {
    const t = raw as {
      nombre?: string;
      nie_raw?: string;
      cliente_id?: string;
      lado?: string;
      cuota_bps?: number;
      inmueble_id?: string;
    };
    const tid = `${t.cliente_id ?? ""}`;
    if (tid && tid === folderClienteId) continue;
    const nombre = `${t.nombre ?? ""}`.trim();
    if (!nombre) continue;
    const bps = Number(t.cuota_bps) || 0;
    items.push({
      nombre,
      nie: `${t.nie_raw ?? ""}`.trim() || null,
      cliente_id: tid || null,
      lado: `${t.lado ?? ""}`.trim() || null,
      share_percent: bps ? bps / 100 : null,
      direccion: addr.get(`${t.inmueble_id ?? ""}`) ?? null,
    });
  }
  return { cliente_id: folderClienteId, total: items.length, items };
}

async function loadFolderProperties(
  client: SupabaseClient,
  folderClienteId: string,
): Promise<unknown> {
  const { data, error } = await client
    .from("inmuebles")
    .select("id, direccion")
    .eq("cliente_id", folderClienteId)
    .is("deleted_at", null)
    .order("created_at", { ascending: true });
  if (error || !Array.isArray(data)) {
    return { cliente_id: folderClienteId, count: 0, addresses: [] };
  }
  const addresses: string[] = [];
  for (const raw of data) {
    const d = `${(raw as { direccion?: string }).direccion ?? ""}`.trim();
    if (d && !addresses.includes(d)) addresses.push(d);
  }
  return {
    cliente_id: folderClienteId,
    count: data.length,
    addresses,
  };
}

function searchDocQueryParts(raw: string): string[] {
  const n = raw.toLowerCase().normalize("NFD").replace(/\p{M}/gu, "");
  const parts: string[] = [];
  const add = (s: string) => {
    if (!parts.includes(s)) parts.push(s);
  };
  if (/(dni|nie|pasport|pasaporte|passport|obcans)/.test(n)) {
    add("dni_nie");
    add("pasaporte");
  }
  if (/(factur|faktura|invoice|rechnung|recibo|ucten)/.test(n)) {
    add("factura");
    add("recibo");
  }
  if (/(email|e-mail|mail|correo|posta|gmail|outlook)/.test(n)) {
    add("email");
    add("correo");
    add("mail");
  }
  if (/(escritur|listin|notar|deed|kupni|compraventa|smlouv)/.test(n)) {
    add("copia_escritura");
    add("escritura");
    add("compraventa");
  }
  if (/(poder|plna moc|attorney)/.test(n)) add("copia_poder");
  if (/(iban|bankov)/.test(n)) add("justificante_iban");
  if (/(ibi|suma|catastr)/.test(n)) add("recibo_ibi");
  if (/(seguro|pojist|alarm)/.test(n)) {
    add("poliza_seguro");
    add("contrato_alarma");
  }
  if (/(scan|sken|pdf|fotka|foto|papir)/.test(n)) add("scan");
  return parts;
}

function looksLikeListPileDocsLoose(raw: string): boolean {
  const n = raw.toLowerCase().normalize("NFD").replace(/\p{M}/gu, "");
  const asksList = /jake|jaky|which|what |que |quels|welche/.test(n);
  const onPile = /hromad|stoh|doklad|dokument|pile|papir/.test(n);
  return asksList && onPile;
}

function looksLikeListPileDocs(raw: string): boolean {
  return looksLikePileDocs(raw) && searchDocQueryParts(raw).length === 0;
}

async function enrichClientHits(
  client: SupabaseClient,
  rows: Array<{ cliente_id?: string; score?: number; matched_via?: string }>,
): Promise<ClientHit[]> {
  const ids = [
    ...new Set(
      rows.map((r) => `${r.cliente_id ?? ""}`).filter((id) => id.length > 0),
    ),
  ];
  if (ids.length === 0) return [];
  const { data } = await client
    .from("clientes")
    .select("id, nombre, apellidos")
    .in("id", ids);
  const names = new Map<string, string>();
  for (const raw of data ?? []) {
    const row = raw as { id?: string; nombre?: string; apellidos?: string };
    const id = `${row.id ?? ""}`;
    const nombre = [row.nombre, row.apellidos]
      .map((s) => `${s ?? ""}`.trim())
      .filter(Boolean)
      .join(" ");
    names.set(id, nombre);
  }
  const byScore = new Map<string, ClientHit>();
  for (const r of rows) {
    const id = `${r.cliente_id ?? ""}`;
    if (!id) continue;
    const score = Number(r.score) || 0;
    const prev = byScore.get(id);
    if (prev && prev.score >= score) continue;
    byScore.set(id, {
      cliente_id: id,
      nombre: names.get(id) ?? "",
      score,
      matched_via: r.matched_via,
    });
  }
  return [...byScore.values()].sort((a, b) => b.score - a.score);
}

async function searchClientHits(
  client: SupabaseClient,
  q: string,
  limit: number,
): Promise<ClientHit[]> {
  const merged: Array<
    { cliente_id?: string; score?: number; matched_via?: string }
  > = [];
  for (const query of searchClientQueries(q)) {
    const { data, error } = await client.rpc("search_clients", {
      p_q: query,
      p_limit: limit,
    });
    if (error || !Array.isArray(data)) continue;
    for (const row of data) {
      if (row && typeof row === "object") {
        merged.push(row as {
          cliente_id?: string;
          score?: number;
          matched_via?: string;
        });
      }
    }
  }
  return (await enrichClientHits(client, merged)).slice(0, limit);
}

async function listClientHits(
  client: SupabaseClient,
  limit: number,
): Promise<ClientHit[]> {
  // Max 20 — stránkovaný výtah, ne dump 100 karet do promptu.
  const capped = Math.min(Math.max(limit, 1), 20);
  const { data, error } = await client
    .from("clientes")
    .select("id, nombre, apellidos")
    .is("deleted_at", null)
    .order("updated_at", { ascending: false })
    .limit(capped);
  if (error || !Array.isArray(data)) return [];
  return data.map((raw) => {
    const row = raw as { id?: string; nombre?: string; apellidos?: string };
    const nombre = [row.nombre, row.apellidos]
      .map((s) => `${s ?? ""}`.trim())
      .filter(Boolean)
      .join(" ");
    return {
      cliente_id: `${row.id ?? ""}`,
      nombre,
      score: 1,
      matched_via: "list",
    };
  }).filter((h) => h.cliente_id);
}

async function searchDocumentHybrid(
  client: SupabaseClient,
  tenantId: string,
  q: string,
  apiKey: string,
  opens: Array<{
    cliente_id: string;
    label: string;
    carpeta: boolean;
    bloque_key?: string;
  }>,
): Promise<unknown> {
  let fts: Record<string, unknown> | null = null;
  if (q.trim().length >= 3) {
    const { data, error } = await client.rpc("search_document_text", {
      p_tenant_id: tenantId,
      p_q: q,
      p_limit: 20,
    });
    if (!error && data && typeof data === "object") {
      fts = data as Record<string, unknown>;
    }
  }

  let semantic: Record<string, unknown> | null = null;
  try {
    const [emb] = await embedTexts(apiKey, [q]);
    const { data, error } = await client.rpc("search_document_chunks", {
      p_tenant_id: tenantId,
      p_query_embedding: emb,
      p_limit: 12,
    });
    if (!error && data && typeof data === "object") {
      semantic = data as Record<string, unknown>;
    }
  } catch (err) {
    console.warn("search_document_chunks", err);
  }

  const merged = mergeSearchHits(fts, semantic);
  collectOpens(merged, opens);
  return merged;
}

function mergeSearchHits(
  fts: Record<string, unknown> | null,
  semantic: Record<string, unknown> | null,
): Record<string, unknown> {
  const byId = new Map<string, Record<string, unknown>>();
  const take = (raw: unknown, via: string) => {
    if (!Array.isArray(raw)) return;
    for (const row of raw) {
      if (!row || typeof row !== "object") continue;
      const item = row as Record<string, unknown>;
      const id = `${item.document_id ?? ""}`;
      if (!id) continue;
      const prev = byId.get(id);
      if (!prev) {
        byId.set(id, { ...item, via: item.via ?? via });
        continue;
      }
      const snippet = `${prev.snippet ?? ""}`;
      const next = `${item.snippet ?? ""}`;
      if (snippet.length < next.length) prev.snippet = item.snippet;
      if (!prev.via) prev.via = via;
      if (via === "vector" && prev.via === "fts") prev.via = "hybrid";
    }
  };
  take(fts?.items, "fts");
  take(semantic?.items, "vector");
  const filled = fts?.filled_on_desk !== false ||
    semantic?.filled_on_desk !== false;
  return {
    total: byId.size,
    filled_on_desk: filled,
    items: [...byId.values()],
  };
}

function supabaseUrl(): string {
  return Deno.env.get("SUPABASE_URL") ?? "";
}
function supabaseAnonKey(): string {
  return Deno.env.get("SUPABASE_ANON_KEY") ?? "";
}
function serviceRoleKey(): string {
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

function json(
  status: number,
  body: Record<string, unknown>,
  req?: Request,
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });
}
