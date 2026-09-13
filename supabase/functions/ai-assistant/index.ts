import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

/**
 * Chat kanceláře. Whitelist tools, žádný save/delete/send.
 * Data jen z RPC v tenantovi volajícího.
 */

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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
      description: "Read one client card, blocks, document fields",
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
      description: "Clients whose escritura has this notary on the desk",
      parameters: {
        type: "object",
        properties: { notary: { type: "string" } },
        required: ["notary"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "search_document_text",
      description:
        "Search saved PDF transcripts (body_text) for a phrase like arras or cláusula. Empty transcript is not proof the clause is missing.",
      parameters: {
        type: "object",
        properties: { q: { type: "string" } },
        required: ["q"],
      },
    },
  },
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
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
        "Office otázky (dodavatel, seguro, notář) = query_* tools. " +
        "Věta ve smlouvě / arras / cláusula = search_document_text. " +
        "Když body_text chybí, neříkej že ve smlouvě věta není — přepis ještě není uložený. " +
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
      collectOpens(data, opens);
      return data;
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
        p_notary: str(args.notary),
      });
      if (error) return { error: error.message };
      collectOpens(data, opens);
      return data;
    }
    case "search_document_text": {
      const q = str(args.q);
      const { data, error } = await client.rpc("search_document_text", {
        p_tenant_id: tenantId,
        p_q: q,
        p_limit: 20,
      });
      if (error) return { error: error.message };
      collectOpens(data, opens);
      return data;
    }
    default:
      return { error: "unknown_tool" };
  }
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
      id?: string;
      nombre?: string;
      original_name?: string;
      bloque_key?: string;
    };
    const id = `${row.cliente_id ?? row.id ?? ""}`;
    if (!id || opens.some((o) => o.cliente_id === id && o.bloque_key === (row.bloque_key ?? ""))) {
      continue;
    }
    const label = `${row.original_name ?? row.nombre ?? id}`;
    opens.push({
      cliente_id: id,
      label,
      carpeta: true,
      bloque_key: row.bloque_key ?? "",
    });
  }
}

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
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

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
