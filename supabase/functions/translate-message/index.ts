import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

/**
 * Překlad výzvy do clientes.locale. Volá jen gestor klikem, ne AI, ne cron.
 * Bez OPENAI_API_KEY vrátí originál — nic se netváří, že se přeložilo.
 */

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

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) {
    return json(401, { ok: false, error: "Unauthorized" });
  }

  const body = await req.json() as {
    text?: unknown;
    source_locale?: unknown;
    target_locale?: unknown;
  };
  const text = typeof body.text === "string" ? body.text : "";
  const source = typeof body.source_locale === "string"
    ? body.source_locale.trim()
    : "es";
  const target = typeof body.target_locale === "string"
    ? body.target_locale.trim()
    : "cs";
  if (!text.trim()) {
    return json(400, { ok: false, error: "text required" });
  }
  if (source === target) {
    return json(200, { ok: true, text, translated: false });
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY")?.trim();
  if (!apiKey) {
    return json(200, { ok: true, text, translated: false });
  }

  const names: Record<string, string> = {
    cs: "Czech",
    en: "English",
    es: "Spanish",
    de: "German",
    fr: "French",
  };
  const targetName = names[target] ?? target;
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
            `Translate the office message into ${targetName}. Keep official terms (NIE, escritura, plusvalía, modelo 210) untranslated. Return only the translation.`,
        },
        { role: "user", content: text },
      ],
    }),
  });
  if (!res.ok) {
    return json(200, { ok: true, text, translated: false });
  }
  const data = await res.json() as {
    choices?: Array<{ message?: { content?: string } }>;
  };
  const translated = data.choices?.[0]?.message?.content?.trim();
  if (!translated) {
    return json(200, { ok: true, text, translated: false });
  }
  return json(200, { ok: true, text: translated, translated: true });
});

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
