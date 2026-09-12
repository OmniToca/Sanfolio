import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

/**
 * Ranní cron: nachystá draft mensajes. Nikdy neodesílá.
 * Auth: CRON_SECRET nebo service_role. AI / gestor sem nepatří.
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

  const token = (req.headers.get("Authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  ).trim();
  const cronSecret = Deno.env.get("CRON_SECRET")?.trim() ?? "";
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
  const allowed = (cronSecret !== "" && token === cronSecret) ||
    (service !== "" && token === service);
  if (!allowed) {
    return json(401, { ok: false, error: "Unauthorized" });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    service,
  );
  const { data, error } = await admin.rpc("run_plazo_reminders", {
    p_force: true,
  });
  if (error) {
    return json(500, { ok: false, error: error.message });
  }
  return json(200, { ok: true, result: data });
});

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
