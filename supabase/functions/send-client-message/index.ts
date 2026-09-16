import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

/**
 * Odeslání výzvy klientovi (Resend). Jen authenticated gestor po kliknutí.
 * Cron ani AI sem nesmí. Bez RESEND_API_KEY → not_configured (Flutter otevře Gmail).
 */

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return json(200, { ok: true });
  }
  if (req.method !== "POST") {
    return json(405, { ok: false, error: "method" });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json(401, { ok: false, error: "unauthorized" });
  }

  const resendKey = Deno.env.get("RESEND_API_KEY")?.trim() ?? "";
  if (!resendKey) {
    return json(503, { ok: false, error: "not_configured" });
  }

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) {
    return json(401, { ok: false, error: "unauthorized" });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json() as Record<string, unknown>;
  } catch {
    return json(400, { ok: false, error: "json" });
  }

  const tenantId = str(body.tenant_id);
  const clienteId = str(body.cliente_id);
  const asunto = str(body.asunto);
  const cuerpoOriginal = str(body.cuerpo_original);
  const outboundBody = str(body.outbound_body);
  const outboundLocale = str(body.outbound_locale) || "es";
  const templateKey = str(body.template_key) || null;
  const postaMessageId = str(body.posta_message_id) || null;
  if (!tenantId || !clienteId || !cuerpoOriginal || !outboundBody) {
    return json(400, { ok: false, error: "payload" });
  }

  const { data: allowed, error: accessErr } = await userClient.rpc(
    "can_access_tenant",
    { _tenant_id: tenantId },
  );
  if (accessErr) return json(500, { ok: false, error: accessErr.message });
  if (allowed !== true) return json(403, { ok: false, error: "forbidden" });

  const { data: cliente, error: cliErr } = await userClient
    .from("clientes")
    .select("id, email, nombre, apellidos, locale")
    .eq("id", clienteId)
    .eq("tenant_id", tenantId)
    .is("deleted_at", null)
    .maybeSingle();
  if (cliErr) return json(500, { ok: false, error: cliErr.message });
  const to = str(cliente?.email).toLowerCase();
  if (!cliente || !to.includes("@")) {
    return json(400, { ok: false, error: "no_email" });
  }

  const { data: settings } = await userClient
    .from("tenant_settings")
    .select("display_name")
    .eq("tenant_id", tenantId)
    .maybeSingle();
  const officeName = str(settings?.display_name) || "Sanfolio";

  const { data: accountRows, error: accErr } = await userClient.rpc(
    "ensure_posta_account",
    { p_tenant_id: tenantId },
  );
  if (accErr) return json(500, { ok: false, error: accErr.message });
  const account = firstRow(accountRows);
  const ingest = str(account?.ingest_address);
  const ingestDomain = str(account?.ingest_domain) ||
    (ingest.includes("@") ? ingest.split("@")[1] : "inbound.sanfolio.app");
  const replyTo = ingest.includes("@")
    ? `${ingest.split("@")[0].split("+")[0]}+${clienteId}@${ingestDomain}`
    : null;

  let inReplyTo: string | null = null;
  if (postaMessageId) {
    const { data: inbound } = await userClient
      .from("posta_messages")
      .select("id, message_id_header, cliente_id")
      .eq("id", postaMessageId)
      .eq("tenant_id", tenantId)
      .is("deleted_at", null)
      .maybeSingle();
    const hid = str(inbound?.message_id_header);
    if (hid) inReplyTo = hid.includes("<") ? hid : `<${hid}>`;
  }

  const mensajeId = crypto.randomUUID();
  const messageIdHeader = `${mensajeId}@${ingestDomain}`;
  // Jedna ověřená From adresa pro všechny kanceláře. Reply-To je per tenant+klient.
  const fromEmail = Deno.env.get("POSTA_FROM_EMAIL")?.trim() ||
    "posta@sanfolio.app";
  if (!fromEmail.includes("@")) {
    return json(503, { ok: false, error: "not_configured" });
  }

  const { error: insErr } = await userClient.from("mensajes").insert({
    id: mensajeId,
    tenant_id: tenantId,
    cliente_id: clienteId,
    canal: "email",
    asunto: asunto || null,
    cuerpo: cuerpoOriginal,
    locale_original: "es",
    translations: { [outboundLocale]: outboundBody },
    status: "draft",
    template_key: templateKey,
    message_id_header: messageIdHeader,
    created_by: userData.user.id,
  });
  if (insErr) return json(500, { ok: false, error: insErr.message });

  const headers: Record<string, string> = {
    "Message-ID": `<${messageIdHeader}>`,
  };
  if (inReplyTo) {
    headers["In-Reply-To"] = inReplyTo;
    headers.References = inReplyTo;
  }

  const sent = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: `${officeName} <${fromEmail}>`,
      to: [to],
      subject: asunto || officeName,
      text: outboundBody,
      reply_to: replyTo || undefined,
      headers,
    }),
  });
  const sentJson = await sent.json().catch(() => ({})) as {
    id?: unknown;
    message?: unknown;
    error?: { message?: unknown };
  };
  if (!sent.ok) {
    await userClient
      .from("mensajes")
      .update({ status: "discarded" })
      .eq("id", mensajeId)
      .eq("tenant_id", tenantId);
    return json(502, {
      ok: false,
      error: "send_failed",
      detail: str(sentJson.error?.message ?? sentJson.message),
    });
  }

  const providerId = str(sentJson.id) || null;
  const { error: updErr } = await userClient
    .from("mensajes")
    .update({
      status: "sent",
      sent_at: new Date().toISOString(),
      provider_message_id: providerId,
    })
    .eq("id", mensajeId)
    .eq("tenant_id", tenantId);
  if (updErr) {
    return json(500, { ok: false, error: updErr.message, id: mensajeId });
  }

  if (postaMessageId) {
    await userClient.rpc("attach_posta_to_mensaje", {
      p_message_id: postaMessageId,
      p_mensaje_id: mensajeId,
    });
  }

  return json(200, { ok: true, id: mensajeId, provider_id: providerId });
});

function str(v: unknown): string {
  if (v == null) return "";
  return String(v).trim();
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

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
