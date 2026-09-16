import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

/**
 * Inbound webhook (Resend / Postmark / generický JSON).
 * Uloží metadata + přílohy. Klienta přiřadí jen unique From nebo plus-adresa.
 * Blok na desce nevybírá — to dělá gestor v /posta.
 *
 * Auth: POSTA_INBOUND_SECRET (Postmark / ruční test) nebo Svix
 * `RESEND_WEBHOOK_SECRET`. Tělo Resendu se stáhne přes RESEND_API_KEY.
 * Ne JWT uživatele.
 */

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-posta-secret, x-webhook-secret, svix-id, svix-timestamp, svix-signature",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MAX_BODY = 200_000;
const MAX_ATTACH = 20;
const MAX_ATTACH_BYTES = 32 * 1024 * 1024;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return json(200, { ok: true });
  }
  if (req.method !== "POST") {
    return json(405, { ok: false, error: "method" });
  }
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
  const url = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
  if (!service || !url) {
    return json(500, { ok: false, error: "not_configured" });
  }

  let rawText = "";
  try {
    rawText = await req.text();
  } catch {
    return json(400, { ok: false, error: "json" });
  }
  if (!(await inboundAuthorized(req, rawText))) {
    return json(401, { ok: false, error: "unauthorized" });
  }

  let raw: unknown;
  try {
    raw = JSON.parse(rawText) as unknown;
  } catch {
    return json(400, { ok: false, error: "json" });
  }

  if (isRecord(raw) && raw.type === "email.received") {
    try {
      const hydrated = await hydrateResendReceived(raw);
      if (!hydrated) {
        return json(400, { ok: false, error: "payload" });
      }
      raw = hydrated;
    } catch (err) {
      const msg = err instanceof Error ? err.message : "resend";
      return json(502, { ok: false, error: msg });
    }
  } else if (isRecord(raw) && typeof raw.type === "string") {
    return json(200, { ok: true, ignored: raw.type });
  }

  const parsed = parseInbound(raw);
  if (!parsed) {
    return json(400, { ok: false, error: "payload" });
  }

  const admin = createClient(url, service, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const recipients = [...parsed.to, ...parsed.cc];
  let resolved: {
    tenant_id: string;
    account_id: string;
    cliente_id: string | null;
  } | null = null;
  for (const addr of recipients) {
    const { data, error } = await admin.rpc("resolve_posta_recipient", {
      p_address: addr,
    });
    if (error) {
      return json(500, { ok: false, error: error.message });
    }
    const row = firstRow(data);
    if (row?.tenant_id && row?.account_id) {
      resolved = {
        tenant_id: String(row.tenant_id),
        account_id: String(row.account_id),
        cliente_id: row.cliente_id ? String(row.cliente_id) : null,
      };
      if (resolved.cliente_id) break;
    }
  }
  if (!resolved) {
    return json(404, { ok: false, error: "unknown_recipient" });
  }

  let clienteId = resolved.cliente_id;
  let matchMethod:
    | "plus_address"
    | "from_email"
    | "remembered"
    | null = clienteId ? "plus_address" : null;
  if (!clienteId) {
    const { data: matched } = await admin.rpc("match_posta_cliente", {
      p_tenant_id: resolved.tenant_id,
      p_email: parsed.from,
    });
    if (typeof matched === "string" && matched.length > 0) {
      clienteId = matched;
      const { data: remembered } = await admin
        .from("posta_senders")
        .select("id")
        .eq("tenant_id", resolved.tenant_id)
        .eq("email", parsed.from)
        .is("deleted_at", null)
        .maybeSingle();
      matchMethod = remembered ? "remembered" : "from_email";
    }
  }

  const gmailUrl = parsed.messageIdHeader
    ? `https://mail.google.com/mail/#search/rfc822msgid:${
      encodeURIComponent(parsed.messageIdHeader)
    }`
    : null;

  const { data: inserted, error: insErr } = await admin
    .from("posta_messages")
    .insert({
      tenant_id: resolved.tenant_id,
      account_id: resolved.account_id,
      provider_message_id: parsed.providerId,
      message_id_header: parsed.messageIdHeader,
      from_address: parsed.from,
      from_name: parsed.fromName,
      to_addresses: parsed.to,
      cc_addresses: parsed.cc,
      subject: parsed.subject,
      body_text: clip(parsed.bodyText, MAX_BODY),
      received_at: parsed.receivedAt,
      in_reply_to: parsed.inReplyTo,
      references_header: parsed.referencesHeader,
      cliente_id: clienteId,
      match_method: matchMethod,
      status: clienteId ? "assigned" : "unassigned",
      gmail_url: gmailUrl,
    })
    .select("id")
    .single();

  if (insErr) {
    if (insErr.code === "23505") {
      return json(200, { ok: true, duplicate: true });
    }
    return json(500, { ok: false, error: insErr.message });
  }
  const messageId = String(inserted.id);
  await admin.rpc("link_posta_reply", { p_message_id: messageId });

  let stored = 0;
  for (const att of parsed.attachments.slice(0, MAX_ATTACH)) {
    if (att.bytes.length === 0 || att.bytes.length > MAX_ATTACH_BYTES) {
      continue;
    }
    const safe = att.filename.replace(/[^A-Za-z0-9._-]/g, "_") || "file";
    const path =
      `${resolved.tenant_id}/posta/${messageId}/${stored}_${safe}`;
    const mime = att.mime || "application/octet-stream";
    const { error: upErr } = await admin.storage.from("documentos").upload(
      path,
      att.bytes,
      { contentType: mime, upsert: false },
    );
    if (upErr) continue;
    const { error: rowErr } = await admin.from("posta_attachments").insert({
      tenant_id: resolved.tenant_id,
      message_id: messageId,
      filename: att.filename,
      mime,
      byte_size: att.bytes.length,
      storage_path: path,
    });
    if (!rowErr) stored += 1;
  }

  return json(200, {
    ok: true,
    id: messageId,
    assigned: Boolean(clienteId),
    attachments: stored,
  });
});

async function inboundAuthorized(req: Request, rawBody: string): Promise<boolean> {
  const secret = Deno.env.get("POSTA_INBOUND_SECRET")?.trim() ?? "";
  if (secret) {
    const bearer = (req.headers.get("Authorization") ?? "").replace(
      /^Bearer\s+/i,
      "",
    ).trim();
    const header = (req.headers.get("x-posta-secret") ??
      req.headers.get("x-webhook-secret") ??
      "").trim();
    if (bearer === secret || header === secret) return true;
  }
  return await verifyResendSvix(req, rawBody);
}

type ParsedInbound = {
  providerId: string;
  messageIdHeader: string | null;
  inReplyTo: string | null;
  referencesHeader: string | null;
  from: string;
  fromName: string | null;
  to: string[];
  cc: string[];
  subject: string | null;
  bodyText: string;
  receivedAt: string;
  attachments: { filename: string; mime: string; bytes: Uint8Array }[];
};

function parseInbound(raw: unknown): ParsedInbound | null {
  if (!raw || typeof raw !== "object") return null;
  const obj = raw as Record<string, unknown>;

  if (isRecord(obj.data) && typeof obj.type === "string") {
    return parseInbound(obj.data);
  }

  if (typeof obj.From === "string" || isRecord(obj.FromFull)) {
    return parsePostmark(obj);
  }

  const to = emailsFrom(obj.to ?? obj.recipient ?? obj.To);
  const fromRaw = stringify(obj.from ?? obj.From ?? obj.sender);
  const from = extractEmail(fromRaw);
  if (!from || to.length === 0) return null;

  const providerId = stringify(
    obj.provider_message_id ?? obj.message_id ?? obj.id ?? obj.MessageID,
  ) || crypto.randomUUID();

  const headers = headerMap(obj.headers ?? obj.Headers);
  return {
    providerId,
    messageIdHeader: stringify(obj.message_id_header ?? obj.MessageID) ||
      headers["message-id"] ||
      null,
    inReplyTo: stringify(obj.in_reply_to) || headers["in-reply-to"] || null,
    referencesHeader: stringify(obj.references) || headers.references || null,
    from,
    fromName: stringify(obj.from_name ?? obj.fromName) || nameFrom(fromRaw),
    to,
    cc: emailsFrom(obj.cc ?? obj.Cc),
    subject: stringify(obj.subject ?? obj.Subject) || null,
    bodyText: stringify(obj.text ?? obj.body ?? obj.body_text ?? obj.TextBody) ||
      stripTags(stringify(obj.html ?? obj.HtmlBody)),
    receivedAt: isoDate(obj.received_at ?? obj.Date ?? obj.created_at),
    attachments: decodeAttachments(obj.attachments ?? obj.Attachments),
  };
}

function parsePostmark(obj: Record<string, unknown>): ParsedInbound | null {
  const fromFull = isRecord(obj.FromFull) ? obj.FromFull : null;
  const from = extractEmail(
    stringify(fromFull?.Email) || stringify(obj.From),
  );
  const to = emailsFrom(obj.ToFull ?? obj.To);
  if (!from || to.length === 0) return null;
  const headers = headerMap(obj.Headers);
  return {
    providerId: stringify(obj.MessageID) || crypto.randomUUID(),
    messageIdHeader: stringify(obj.MessageID) || headers["message-id"] ||
      null,
    inReplyTo: headers["in-reply-to"] || null,
    referencesHeader: headers.references || null,
    from,
    fromName: stringify(fromFull?.Name) || nameFrom(stringify(obj.From)),
    to,
    cc: emailsFrom(obj.CcFull ?? obj.Cc),
    subject: stringify(obj.Subject) || null,
    bodyText: stringify(obj.TextBody) || stripTags(stringify(obj.HtmlBody)),
    receivedAt: isoDate(obj.Date),
    attachments: decodeAttachments(obj.Attachments),
  };
}

function decodeAttachments(raw: unknown): ParsedInbound["attachments"] {
  if (!Array.isArray(raw)) return [];
  const out: ParsedInbound["attachments"] = [];
  for (const item of raw) {
    if (!isRecord(item)) continue;
    const filename = stringify(item.filename ?? item.Name ?? item.name) ||
      "file";
    const mime = stringify(
      item.mime ?? item.ContentType ?? item.content_type ?? item.type,
    ) || "application/octet-stream";
    const b64 = stringify(item.content ?? item.Content ?? item.data);
    if (!b64) continue;
    try {
      const bin = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
      out.push({ filename, mime, bytes: bin });
    } catch {
      // Poškozená příloha nesmí shodit celý mail.
    }
  }
  return out;
}

function emailsFrom(raw: unknown): string[] {
  const out: string[] = [];
  const push = (v: string) => {
    const e = extractEmail(v);
    if (e && !out.includes(e)) out.push(e);
  };
  if (typeof raw === "string") {
    for (const part of raw.split(/[,;]/)) push(part);
    return out;
  }
  if (Array.isArray(raw)) {
    for (const item of raw) {
      if (typeof item === "string") push(item);
      else if (isRecord(item)) {
        push(stringify(item.Email ?? item.email ?? item.address));
      }
    }
  }
  return out;
}

function extractEmail(raw: string): string {
  const angle = raw.match(/<([^>]+)>/);
  const v = (angle?.[1] ?? raw).trim().toLowerCase();
  return v.includes("@") ? v : "";
}

function nameFrom(raw: string): string | null {
  const trimmed = raw.replace(/<[^>]+>/, "").trim().replace(/^"|"$/g, "");
  return trimmed.length > 0 && !trimmed.includes("@") ? trimmed : null;
}

function stripTags(html: string): string {
  return html.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
}

function clip(s: string, max: number): string {
  return s.length <= max ? s : s.slice(0, max);
}

function isoDate(raw: unknown): string {
  const s = stringify(raw);
  const d = s ? new Date(s) : new Date();
  return Number.isNaN(d.getTime()) ? new Date().toISOString() : d.toISOString();
}

function stringify(v: unknown): string {
  if (v == null) return "";
  return String(v).trim();
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return Boolean(v) && typeof v === "object" && !Array.isArray(v);
}

function headerMap(raw: unknown): Record<string, string> {
  const out: Record<string, string> = {};
  const put = (k: string, v: string) => {
    const key = k.trim().toLowerCase();
    const val = v.trim();
    if (key && val) out[key] = val;
  };
  if (isRecord(raw)) {
    for (const [k, v] of Object.entries(raw)) {
      if (typeof v === "string") put(k, v);
    }
    return out;
  }
  if (!Array.isArray(raw)) return out;
  for (const item of raw) {
    if (!isRecord(item)) continue;
    put(
      stringify(item.Name ?? item.name ?? item.key),
      stringify(item.Value ?? item.value),
    );
  }
  return out;
}

function firstRow(data: unknown): Record<string, unknown> | null {
  if (Array.isArray(data) && data[0] && typeof data[0] === "object") {
    return data[0] as Record<string, unknown>;
  }
  if (data && typeof data === "object" && !Array.isArray(data)) {
    return data as Record<string, unknown>;
  }
  return null;
}

/** Resend webhook: metadata → tělo + bajty příloh. */
async function hydrateResendReceived(
  event: Record<string, unknown>,
): Promise<Record<string, unknown> | null> {
  const data = isRecord(event.data) ? event.data : null;
  const emailId = stringify(data?.email_id);
  if (!emailId) return null;
  const key = Deno.env.get("RESEND_API_KEY")?.trim() ?? "";
  if (!key) throw new Error("not_configured");

  const email = await resendJson(
    `https://api.resend.com/emails/receiving/${emailId}`,
    key,
  );
  if (!email) throw new Error("resend_email");

  const headerSrc = isRecord(email.headers) ? email.headers : {};
  const to = [
    ...emailsFrom(email.to),
    ...emailsFrom(email.received_for),
    ...emailsFrom(data?.to),
    ...emailsFrom(data?.received_for),
  ];
  const fromRaw = stringify(headerSrc.from) || stringify(email.from) ||
    stringify(data?.from);
  return {
    provider_message_id: emailId,
    message_id_header: stringify(email.message_id) ||
      stringify(data?.message_id),
    from: fromRaw,
    from_name: nameFrom(fromRaw),
    to,
    cc: emailsFrom(email.cc),
    subject: stringify(email.subject) || stringify(data?.subject),
    text: stringify(email.text) || stripTags(stringify(email.html)),
    received_at: stringify(email.created_at) || stringify(data?.created_at),
    headers: headerSrc,
    attachments: await downloadResendAttachments(emailId, key),
  };
}

async function downloadResendAttachments(
  emailId: string,
  apiKey: string,
): Promise<{ filename: string; mime: string; content: string }[]> {
  const listed = await resendJson(
    `https://api.resend.com/emails/receiving/${emailId}/attachments`,
    apiKey,
  );
  const rows = listed && Array.isArray(listed.data) ? listed.data : [];
  const out: { filename: string; mime: string; content: string }[] = [];
  for (const item of rows.slice(0, MAX_ATTACH)) {
    if (!isRecord(item)) continue;
    const url = stringify(item.download_url);
    if (!url) continue;
    const size = Number(item.size ?? 0);
    if (size > MAX_ATTACH_BYTES) continue;
    try {
      const res = await fetch(url);
      if (!res.ok) continue;
      const buf = new Uint8Array(await res.arrayBuffer());
      if (buf.length === 0 || buf.length > MAX_ATTACH_BYTES) continue;
      let b64 = "";
      const chunk = 0x8000;
      for (let i = 0; i < buf.length; i += chunk) {
        b64 += String.fromCharCode(...buf.subarray(i, i + chunk));
      }
      out.push({
        filename: stringify(item.filename) || "file",
        mime: stringify(item.content_type) || "application/octet-stream",
        content: btoa(b64),
      });
    } catch {
      // Jedna příloha nesmí shodit mail.
    }
  }
  return out;
}

async function resendJson(
  url: string,
  apiKey: string,
): Promise<Record<string, unknown> | null> {
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${apiKey}` },
  });
  if (!res.ok) return null;
  const body = await res.json() as unknown;
  return isRecord(body) ? body : null;
}

async function verifyResendSvix(req: Request, rawBody: string): Promise<boolean> {
  const secret = Deno.env.get("RESEND_WEBHOOK_SECRET")?.trim() ?? "";
  if (!secret) return false;
  const id = (req.headers.get("svix-id") ?? "").trim();
  const ts = (req.headers.get("svix-timestamp") ?? "").trim();
  const sigHeader = (req.headers.get("svix-signature") ?? "").trim();
  if (!id || !ts || !sigHeader) return false;
  const b64 = secret.startsWith("whsec_") ? secret.slice("whsec_".length) : secret;
  let keyBytes: Uint8Array;
  try {
    keyBytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  } catch {
    return false;
  }
  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = new TextEncoder().encode(`${id}.${ts}.${rawBody}`);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, signed));
  const digest = btoa(String.fromCharCode(...mac));
  for (const part of sigHeader.split(/[\s,]+/)) {
    const val = part.trim();
    const hex = val.startsWith("v1=")
      ? val.slice(3)
      : val.startsWith("v1,")
      ? val.slice(3)
      : val;
    if (hex && timingSafeEqual(hex, digest)) return true;
  }
  return false;
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let n = 0;
  for (let i = 0; i < a.length; i++) {
    n |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return n === 0;
}

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
