import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { extractPdfPages, pdfTextUsable } from "../_shared/pdf_extract.ts";

/**
 * Fotka / PDF → návrh do ai_drafts. Nikdy neukládá klienta ani neodesílá.
 * HTTP vrátí pending hned; LLM doběhne na pozadí (waitUntil). Guardar je gestor.
 */

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const IMAGE_MIME = new Set(["image/jpeg", "image/png", "image/webp", "image/heic"]);
const MAX_BYTES = 12 * 1024 * 1024;

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
  if (!storagePath.startsWith(`${tenantId}/${clienteId}/`)) {
    return json(403, { ok: false, error: "path outside cliente" });
  }

  const { data: allowed, error: accessErr } = await userClient.rpc(
    "can_access_tenant",
    { _tenant_id: tenantId },
  );
  if (accessErr) return json(500, { ok: false, error: accessErr.message });
  if (allowed !== true) return json(403, { ok: false, error: "forbidden" });

  const { data: draft, error: insErr } = await userClient
    .from("ai_drafts")
    .insert({
      tenant_id: tenantId,
      cliente_id: clienteId,
      created_by: userData.user.id,
      purpose: "extract_document",
      target: "documento",
      bloque_key: bloqueKey,
      fields: { extract_status: "pending" },
      storage_path: storagePath,
    })
    .select("id")
    .single();
  if (insErr || !draft) {
    return json(500, { ok: false, error: insErr?.message ?? "draft insert failed" });
  }

  const work = finishExtract({
    userClient,
    userId: userData.user.id,
    tenantId,
    draftId: `${draft.id}`,
    storagePath,
    mime,
    docTipo,
    bloqueKey,
  });
  keepAlive(work);

  return json(200, {
    ok: true,
    pending: true,
    extracted: false,
    draft_id: draft.id,
    bloque_key: bloqueKey,
    fields: { extract_status: "pending" },
  });
});

function keepAlive(work: Promise<unknown>) {
  const rt = (globalThis as {
    EdgeRuntime?: { waitUntil: (p: Promise<unknown>) => void };
  }).EdgeRuntime;
  if (rt?.waitUntil) {
    rt.waitUntil(work);
    return;
  }
  void work;
}

async function finishExtract(args: {
  userClient: ReturnType<typeof createClient>;
  userId: string;
  tenantId: string;
  draftId: string;
  storagePath: string;
  mime: string;
  docTipo: string;
  bloqueKey: string;
}) {
  try {
    const { data: file, error: dlErr } = await args.userClient.storage
      .from("documentos")
      .download(args.storagePath);
    if (dlErr || !file) {
      await markDraft(args.userClient, args.draftId, { extract_status: "failed" });
      return;
    }
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (bytes.byteLength > MAX_BYTES) {
      await markDraft(args.userClient, args.draftId, { extract_status: "failed" });
      return;
    }

    const isPdf = args.mime === "application/pdf" ||
      /\.pdf$/i.test(args.storagePath);
    const identity = args.docTipo === "dni_nie" || args.docTipo === "pasaporte";
    let fields: Record<string, string> = {};
    if (!isPdf) {
      fields = sanitizeFields(fieldsFromText(latinText(bytes)));
    } else {
      try {
        const pages = await extractPdfPages(bytes);
        if (pdfTextUsable(pages.text)) {
          fields = sanitizeFields(fieldsFromText(pages.text));
          fields.body_text = pages.text.slice(0, 100000);
        }
      } catch (err) {
        console.warn("extract-document: unpdf selhal", err);
      }
    }

    const apiKey = Deno.env.get("OPENAI_API_KEY")?.trim();
    const isImage = IMAGE_MIME.has(args.mime) || looksLikeImage(args.storagePath);
    const needVision = apiKey && (
      isImage ||
      (isPdf && (identity || !fields.body_text))
    );
    if (needVision) {
      const vision = await visionExtract(
        apiKey!,
        bytes,
        args.mime || guessMime(args.storagePath),
        args.docTipo,
        isPdf,
      );
      if (vision) {
        const body = fields.body_text;
        fields = { ...fields, ...sanitizeFields(vision) };
        if (body && !fields.body_text) fields.body_text = body;
      }
    }
    if (apiKey && fields.body_text && !identity) {
      const llm = await llmExtractFromText(apiKey, fields.body_text, args.docTipo);
      if (llm) {
        const body = fields.body_text;
        fields = { ...fields, ...sanitizeFields(llm) };
        fields.body_text = body;
      }
    }
    const extracted = Object.keys(fields).length > 0;
    await markDraft(
      args.userClient,
      args.draftId,
      extracted ? fields : { extract_status: "failed" },
    );
    const admin = createClient(supabaseUrl(), serviceRoleKey(), {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    await admin.from("audit_logs").insert({
      tenant_id: args.tenantId,
      actor_id: args.userId,
      action: "ai.tool",
      entity_table: "ai_drafts",
      entity_id: args.draftId,
      after: { tool: "extract_document", extracted, bloque_key: args.bloqueKey },
    });
  } catch (err) {
    console.warn("extract-document: pozadí", err);
    await markDraft(args.userClient, args.draftId, { extract_status: "failed" });
  }
}

async function markDraft(
  userClient: ReturnType<typeof createClient>,
  draftId: string,
  fields: Record<string, string>,
) {
  await userClient.from("ai_drafts").update({
    fields,
    updated_at: new Date().toISOString(),
  }).eq("id", draftId);
}

const FIELD_MAP: Record<string, string> = {
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
  contractNo: "fields.contractNo",
  invoiceNo: "fields.invoiceNo",
  cups: "fields.cups",
  period: "fields.period",
  periodFrom: "fields.periodFrom",
  periodTo: "fields.periodTo",
  consumption: "fields.consumption",
  amount: "fields.amount",
  notary: "fields.notary",
  protocol: "fields.protocol",
  date: "fields.date",
  company: "fields.company",
  policy: "fields.policy",
  attorney: "fields.attorney",
  body_text: "body_text",
};

const EXTRACT_KEY_LIST = Object.keys(FIELD_MAP).join(",");

function extractSystemPrompt(docTipo: string, includeBody: boolean): string {
  return (
    `Extract fields from a Spanish gestoría document (declared type: ${docTipo || "unknown"}). ` +
    "It may be a factura even if the type says contrato. Keep official terms (NIE, CUPS, escritura). " +
    `Return JSON only with keys you actually see: ${EXTRACT_KEY_LIST}. ` +
    "Nº de contrato / póliza → contractNo. Nº de cliente → clientNo. Nº factura → invoiceNo. " +
    "Periodo de facturación → periodFrom and periodTo (YYYY-MM-DD), not period (period is IBI year only). " +
    "Fecha de emisión → issued. Importe total → amount as 188.85 (dot, no currency). " +
    "Consumo kWh or m³ → consumption. Compañía / comercializadora → company. Titular → holder. " +
    "Dates YYYY-MM-DD. Omit unknown. Do not invent." +
    (includeBody
      ? " body_text = readable text with --- Strana n --- page marks, max 20000 chars."
      : " Do not return body_text.")
  );
}

function mapLlmFields(parsed: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [src, dest] of Object.entries(FIELD_MAP)) {
    const v = str(parsed[src]);
    if (!v) continue;
    out[dest] = src === "nie" ? v.toUpperCase() : src === "email" ? v.toLowerCase() : v;
  }
  return out;
}

function fieldsFromText(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  const nie = text.match(/\b(?:[XYZ][0-9*]{7}[A-Z]|[0-9*]{8}[A-Z])\b/i);
  if (nie) out["fields.nie"] = nie[0].toUpperCase();
  const email = text.match(/[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/i);
  if (email) out["fields.email"] = email[0].toLowerCase();
  const tel = text.match(/\+?\d[\d \-]{7,14}\d/);
  if (tel) {
    const compact = tel[0].replace(/[^\d+]/g, "");
    if (looksLikeTel(compact)) out["fields.tel"] = compact;
  }
  const iso = text.match(/\b(20\d{2}|19\d{2})[-/.](0[1-9]|1[0-2])[-/.](0[1-9]|[12]\d|3[01])\b/);
  if (iso) out["fields.date"] = iso[0].replace(/[/]/g, "-");
  const kwh = text.match(/(\d+[.,]?\d*)\s*kWh/i);
  if (kwh) out["fields.consumption"] = kwh[1].replace(",", ".");
  const m3 = text.match(/(\d+[.,]?\d*)\s*m[³3]/i);
  if (m3 && !out["fields.consumption"]) {
    out["fields.consumption"] = m3[1].replace(",", ".");
  }
  const cups = text.match(
    /\b(ES\s*\d{4}\s*\d{4}\s*\d{4}\s*\d{4}\s*[A-Z]{2})\b/i,
  );
  if (cups) out["fields.cups"] = cups[1].replace(/\s+/g, " ").toUpperCase();
  const contrato = text.match(
    /n[ºo°.]?\s*(?:de\s+)?contrato\s*[:.\s]+([0-9][0-9.\-\/]{4,24})/i,
  );
  if (contrato) out["fields.contractNo"] = contrato[1].replace(/[^\d]/g, "");
  return sanitizeFields(out);
}

function looksLikeNie(raw: string): boolean {
  const v = raw.toUpperCase().replace(/[\s\-\./]/g, "");
  return /^[XYZ][0-9*]{7}[A-Z]$/.test(v) || /^[0-9*]{8}[A-Z]$/.test(v);
}

function looksLikeTel(raw: string): boolean {
  const digits = raw.replace(/[^\d]/g, "");
  if (digits.length < 9 || digits.length > 15) return false;
  const zeros = [...digits].filter((c) => c === "0").length;
  return zeros <= Math.floor(digits.length / 2);
}

function sanitizeFields(raw: Record<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(raw)) {
    const v = value.trim();
    if (!v) continue;
    if (key === "fields.nie") {
      if (looksLikeNie(v)) out[key] = v.toUpperCase().replace(/\s/g, "");
      continue;
    }
    if (key === "fields.tel") {
      if (looksLikeTel(v)) out[key] = v.replace(/[^\d+]/g, "");
      continue;
    }
    if (key === "fields.email") {
      if (v.includes("@") && v.length <= 120) out[key] = v.toLowerCase();
      continue;
    }
    if (key === "body_text") {
      out[key] = v.slice(0, 100000);
      continue;
    }
    if (v.length <= 200) out[key] = v;
  }
  return out;
}

async function llmExtractFromText(
  apiKey: string,
  text: string,
  docTipo: string,
): Promise<Record<string, string> | null> {
  const clipped = text.slice(0, 16000);
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      temperature: 0,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: extractSystemPrompt(docTipo, false) },
        { role: "user", content: clipped },
      ],
    }),
  });
  if (!res.ok) {
    console.warn("extract-document: text LLM HTTP", res.status);
    return null;
  }
  const data = await res.json() as {
    choices?: Array<{ message?: { content?: string } }>;
  };
  const raw = data.choices?.[0]?.message?.content?.trim() ?? "";
  return parseLlmJson(raw);
}

function parseLlmJson(raw: string): Record<string, string> | null {
  const jsonMatch = raw.match(/\{[\s\S]*\}/);
  if (!jsonMatch) return null;
  try {
    const parsed = JSON.parse(jsonMatch[0]) as Record<string, unknown>;
    return mapLlmFields(parsed);
  } catch {
    return null;
  }
}

async function visionExtract(
  apiKey: string,
  bytes: Uint8Array,
  mime: string,
  docTipo: string,
  isPdf = false,
): Promise<Record<string, string> | null> {
  const b64 = bytesToB64(bytes);
  const userContent = isPdf
    ? [
      { type: "text", text: "Document PDF." },
      {
        type: "file",
        file: {
          filename: "document.pdf",
          file_data: `data:application/pdf;base64,${b64}`,
        },
      },
    ]
    : [
      { type: "text", text: "Document image." },
      {
        type: "image_url",
        image_url: { url: `data:${mime};base64,${b64}` },
      },
    ];
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
          content: extractSystemPrompt(docTipo, true),
        },
        {
          role: "user",
          content: userContent,
        },
      ],
    }),
  });
  if (!res.ok) return null;
  const data = await res.json() as {
    choices?: Array<{ message?: { content?: string } }>;
  };
  const raw = data.choices?.[0]?.message?.content?.trim() ?? "";
  const mapped = parseLlmJson(raw);
  if (!mapped) return fieldsFromText(raw);
  return { ...fieldsFromText(raw), ...mapped };
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
  if (/\.pdf$/i.test(path)) return "application/pdf";
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
