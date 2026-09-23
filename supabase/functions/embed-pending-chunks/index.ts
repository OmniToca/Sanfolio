import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { replaceDocumentoChunks } from "../_shared/embed_chunks.ts";

/**
 * Dopočítá kousky u přepisů bez indexu. JWT kanceláře = její tenant.
 * Service role = dávka napříč (backfill z CLI). AI neukládá desku.
 */

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json(405, { ok: false, error: "Method not allowed" });
  }
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.replace(/^Bearer\s+/i, "").trim();
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
  const isService = Boolean(bearer) && (
    (Boolean(serviceKey) && bearer === serviceKey) ||
    jwtRole(bearer) === "service_role"
  );

  const userClient = createClient(supabaseUrl(), supabaseAnonKey(), {
    global: { headers: { Authorization: authHeader } },
  });
  const admin = createClient(supabaseUrl(), serviceKey || supabaseAnonKey());

  let tenantId = "";
  if (!isService) {
    if (!authHeader.toLowerCase().startsWith("bearer ")) {
      return json(401, { ok: false, error: "Missing Authorization" });
    }
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) {
      return json(401, { ok: false, error: "Unauthorized" });
    }
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

  const db = isService ? admin : userClient;
  const pending: Array<{
    id: string;
    body_text: string;
  }> = [];
  let offset = 0;
  let scanned = 0;
  while (pending.length < 8 && offset < 400) {
    let q = db
      .from("documentos")
      .select("id, tenant_id, cliente_id, body_text")
      .is("deleted_at", null)
      .not("body_text", "is", null)
      .range(offset, offset + 19);
    if (tenantId) q = q.eq("tenant_id", tenantId);
    const { data: rows, error } = await q;
    if (error) return json(500, { ok: false, error: error.message });
    const batch = rows ?? [];
    scanned += batch.length;
    if (batch.length === 0) break;
    for (const raw of batch) {
      const id = `${raw.id ?? ""}`;
      const body = `${raw.body_text ?? ""}`.trim();
      if (!id || body.length < 40) continue;
      const { count } = await db
        .from("documento_chunks")
        .select("id", { count: "exact", head: true })
        .eq("documento_id", id)
        .is("deleted_at", null);
      if ((count ?? 0) > 0) continue;
      pending.push({ id, body_text: body });
      if (pending.length >= 8) break;
    }
    offset += 20;
  }

  let done = 0;
  for (const row of pending) {
    try {
      await replaceDocumentoChunks({
        userClient: isService ? admin : userClient,
        documentoId: row.id,
        body: row.body_text,
        apiKey,
      });
      done += 1;
    } catch (err) {
      console.warn("embed-pending", row.id, err);
    }
  }

  return json(200, { ok: true, done, scanned, pending: pending.length });
});

function supabaseUrl(): string {
  return Deno.env.get("SUPABASE_URL") ?? "";
}

function supabaseAnonKey(): string {
  return Deno.env.get("SUPABASE_ANON_KEY") ?? "";
}

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function jwtRole(token: string): string {
  try {
    const payload = token.split(".")[1] ?? "";
    const json = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
    const data = JSON.parse(json) as { role?: string };
    return `${data.role ?? ""}`;
  } catch {
    return "";
  }
}
