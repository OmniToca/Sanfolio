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
      description: "Find clients by name, NIE, phone, email",
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
  };
  const message = typeof body.message === "string" ? body.message.trim() : "";
  const locale = typeof body.locale === "string" ? body.locale.trim() : "cs";
  const clienteId = typeof body.cliente_id === "string"
    ? body.cliente_id.trim()
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
  const messages: Array<Record<string, unknown>> = [
    {
      role: "system",
      content:
        `Jsi asistent španělské gestoría. Odpovídej jazykem ${locale}. ` +
        "Data čteš jen tools. Nevymýšlíš NIE ani doložky. Neříkej, že jsi uložil. " +
        "Prázdné pole na desce ≠ neexistuje smlouva — řekni, že to na desce není vyplněné. " +
        "Částka na desce dodávky není součet faktur. Součet je invoice_glance / fields.amount na dokumentech (kladné; dobropis ne). " +
        "Office otázky (dodavatel, seguro, notář, právník, catastral, strana ve smlouvě) = query_* tools. " +
        "Věta / doložka ve smlouvě = search_document_text (přepis; rozumí i lidské otázce, nemusí to být přesný právní termín). " +
        "Když body_text chybí, neříkej že ve smlouvě věta není — přepis ještě není uložený. " +
        "get_cliente.titular_inmuebles: spoluvlastník na finca složky folder_cliente_id. " +
        "search_document_text a get_cliente.documentos: albums [] = hromada; jinak template_key alb. inmueble_id / direccion = finca. Stejný PDF může být ve víc albech jedné finca. " +
        "Cena domu = sale_price celé listiny; podíl = share_percent. Prázdné documentos[] na kartě titulare ≠ dům nemáme. " +
        "Open = deska složky folder_cliente_id (/carpeta), ne šanon escritura (může být vypnutý) a ne prázdná karta spoluvlastníka. " +
        (clienteId ? `Otevřená karta: ${clienteId}. ` : ""),
    },
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
      const { data, error } = await client.rpc("search_clients", {
        p_q: q,
        p_limit: 10,
      });
      if (error) return { error: error.message };
      return data;
    }
    case "get_cliente": {
      const id = str(args.cliente_id);
      const { data, error } = await client.rpc("ai_get_cliente", {
        p_cliente_id: id,
      });
      if (error) return { error: error.message };
      collectClienteOpens(data, opens);
      return attachInvoiceGlance(data);
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
