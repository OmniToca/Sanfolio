import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

/**
 * Fotka / PDF → návrh do ai_drafts. Nikdy neukládá klienta ani neodesílá.
 * Bez OPENAI_API_KEY zkusí jen hrubý text (PDF) / prázdný návrh — nic se netváří.
 */

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const IMAGE_MIME = new Set(["image/jpeg", "image/png", "image/webp", "image/heic"]);
const MAX_BYTES = 4 * 1024 * 1024;

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
    tenant_id?: unknown;
    cliente_id?: unknown;
    storage_path?: unknown;
    mime?: unknown;
    doc_tipo?: unknown;
    bloque_key?: unknown;
  };
  const tenantId = typeof body.tenant_id === "string" ? body.tenant_id.trim() : "";
  const clienteId = typeof body.cliente_id === "string" ? body.cliente_id.trim() : "";
  const storagePath = typeof body.storage_path === "string"
    ? body.storage_path.trim()
    : "";
  const mime = typeof body.mime === "string" ? body.mime.trim() : "";
  const docTipo = typeof body.doc_tipo === "string" ? body.doc_tipo.trim() : "";
  const bloqueKey = typeof body.bloque_key === "string" && body.bloque_key.trim()
    ? body.bloque_key.trim()
    : "cliente_snapshot";
  if (!tenantId || !clienteId || !storagePath) {
    return json(400, { ok: false, error: "tenant_id, cliente_id, storage_path required" });
  }
  if (!storagePath.startsWith(`${tenantId}/`)) {
    return json(403, { ok: false, error: "path outside tenant" });
  }

  const { data: allowed, error: accessErr } = await userClient.rpc(
    "can_access_tenant",
    { _tenant_id: tenantId },
  );
  if (accessErr) return json(500, { ok: false, error: accessErr.message });
  if (allowed !== true) return json(403, { ok: false, error: "forbidden" });

  const { data: file, error: dlErr } = await userClient.storage
    .from("documentos")
    .download(storagePath);
  if (dlErr || !file) {
    return json(404, { ok: false, error: "file not found" });
  }
  const bytes = new Uint8Array(await file.arrayBuffer());
  if (bytes.byteLength > MAX_BYTES) {
    return json(413, { ok: false, error: "file too large" });
  }

  const latin = latinText(bytes);
  let fields = fieldsFromText(latin);
  let extracted = Object.keys(fields).length > 0;

  const apiKey = Deno.env.get("OPENAI_API_KEY")?.trim();
  const isImage = IMAGE_MIME.has(mime) || looksLikeImage(storagePath);
  if (apiKey && isImage) {
    const vision = await visionExtract(
      apiKey,
      bytes,
      mime || guessMime(storagePath),
      docTipo,
    );
    if (vision) {
      fields = { ...fields, ...vision };
      extracted = true;
    }
  }

  const { data: draft, error: insErr } = await userClient
    .from("ai_drafts")
    .insert({
      tenant_id: tenantId,
      cliente_id: clienteId,
      created_by: userData.user.id,
      purpose: "extract_document",
      target: "documento",
      bloque_key: bloqueKey,
      fields,
      storage_path: storagePath,
    })
    .select("id")
    .single();
  if (insErr || !draft) {
    return json(500, { ok: false, error: insErr?.message ?? "draft insert failed" });
  }

  const admin = createClient(supabaseUrl(), serviceRoleKey(), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  await admin.from("audit_logs").insert({
    tenant_id: tenantId,
    actor_id: userData.user.id,
    action: "ai.tool",
    entity_table: "ai_drafts",
    entity_id: draft.id,
    after: { tool: "extract_document", extracted },
  });

  return json(200, {
    ok: true,
    extracted,
    draft_id: draft.id,
    bloque_key: bloqueKey,
    fields,
  });
});

function fieldsFromText(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  const nie = text.match(/\b[XYZ]\d{0,3}\*{0,4}\d{0,4}[A-Z]\b/i);
  if (nie) out["fields.nie"] = nie[0].toUpperCase();
  const email = text.match(/[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/i);
  if (email) out["fields.email"] = email[0].toLowerCase();
  const tel = text.match(/\+?\d[\d \-]{7,}\d/);
  if (tel) {
    const compact = tel[0].replace(/[^\d+]/g, "");
    if (compact.length >= 8) out["fields.tel"] = compact;
  }
  const iso = text.match(/\b(20\d{2}|19\d{2})[-/.](0[1-9]|1[0-2])[-/.](0[1-9]|[12]\d|3[01])\b/);
  if (iso) out["fields.date"] = iso[0].replace(/[/]/g, "-");
  const kwh = text.match(/(\d+[.,]?\d*)\s*kWh/i);
  if (kwh) out["fields.consumption"] = kwh[1].replace(",", ".");
  return out;
}

async function visionExtract(
  apiKey: string,
  bytes: Uint8Array,
  mime: string,
  docTipo: string,
): Promise<Record<string, string> | null> {
  const b64 = bytesToB64(bytes);
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      temperature: 0,
      messages: [
        {
          role: "system",
          content:
            `Extract fields from a Spanish gestoría document (type: ${docTipo || "unknown"}). ` +
            "Keep official terms (NIE, escritura). Return JSON only with keys you actually see: " +
            "nombre,nie,docNumber,issued,expiry,nationality,holder,clientNo,cups,period,consumption,amount,notary,protocol,date,company,policy,attorney,email,tel. " +
            "Dates YYYY-MM-DD. Amounts like 123.45. Omit unknown. Do not invent.",
        },
        {
          role: "user",
          content: [
            { type: "text", text: "Document image." },
            {
              type: "image_url",
              image_url: { url: `data:${mime};base64,${b64}` },
            },
          ],
        },
      ],
    }),
  });
  if (!res.ok) return null;
  const data = await res.json() as {
    choices?: Array<{ message?: { content?: string } }>;
  };
  const raw = data.choices?.[0]?.message?.content?.trim() ?? "";
  const jsonMatch = raw.match(/\{[\s\S]*\}/);
  if (!jsonMatch) return fieldsFromText(raw);
  try {
    const parsed = JSON.parse(jsonMatch[0]) as Record<string, unknown>;
    const map: Record<string, string> = {
      nie: "fields.nie",
      nombre: "fields.nombre",
      email: "fields.email",
      tel: "fields.tel",
      docNumber: "fields.docNumber",
      issued: "fields.issued",
      expiry: "fields.expiry",
      nationality: "fields.nationality",
      holder: "fields.holder",
      clientNo: "fields.clientNo",
      cups: "fields.cups",
      period: "fields.period",
      consumption: "fields.consumption",
      amount: "fields.amount",
      notary: "fields.notary",
      protocol: "fields.protocol",
      date: "fields.date",
      company: "fields.company",
      policy: "fields.policy",
      attorney: "fields.attorney",
    };
    const out: Record<string, string> = {};
    for (const [src, dest] of Object.entries(map)) {
      const v = str(parsed[src]);
      if (!v) continue;
      out[dest] = src === "nie" ? v.toUpperCase() : src === "email" ? v.toLowerCase() : v;
    }
    return { ...fieldsFromText(raw), ...out };
  } catch {
    return fieldsFromText(raw);
  }
}

function str(v: unknown): string {
  if (typeof v !== "string") return "";
  return v.trim();
}

function latinText(bytes: Uint8Array): string {
  let out = "";
  for (const b of bytes) {
    if (b >= 32 && b < 127) out += String.fromCharCode(b);
    else if (b === 10 || b === 13) out += " ";
  }
  return out;
}

function looksLikeImage(path: string): boolean {
  return /\.(jpe?g|png|webp|heic)$/i.test(path);
}

function guessMime(path: string): string {
  if (/\.png$/i.test(path)) return "image/png";
  if (/\.webp$/i.test(path)) return "image/webp";
  if (/\.heic$/i.test(path)) return "image/heic";
  return "image/jpeg";
}

function bytesToB64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
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
