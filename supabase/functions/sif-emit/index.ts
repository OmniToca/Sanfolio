import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

/**
 * Koncept vydané → JSON SIF dodavatele. Flutter sem nestrká klíč ani XML AEAT.
 * Bez SIF_API_URL vrátí sif_not_configured — sandbox se zapíná env, ne commitem.
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
    factura_id?: unknown;
  };
  const tenantId = typeof body.tenant_id === "string" ? body.tenant_id.trim() : "";
  const facturaId = typeof body.factura_id === "string"
    ? body.factura_id.trim()
    : "";
  if (!tenantId || !facturaId) {
    return json(400, { ok: false, error: "tenant_id, factura_id required" });
  }

  const { data: allowed, error: accessErr } = await userClient.rpc(
    "can_access_tenant",
    { _tenant_id: tenantId },
  );
  if (accessErr) return json(500, { ok: false, error: accessErr.message });
  if (allowed !== true) return json(403, { ok: false, error: "forbidden" });

  const { data: factura, error: factErr } = await userClient
    .from("facturas")
    .select(
      "id, tenant_id, direccion, estado, serie, numero, fecha, concepto, " +
        "destinatario_nombre, destinatario_nif, base_cents, iva_cents, " +
        "iva_bps, total_cents, sif_external_id, sif_status",
    )
    .eq("id", facturaId)
    .eq("tenant_id", tenantId)
    .is("deleted_at", null)
    .maybeSingle();
  if (factErr) return json(500, { ok: false, error: factErr.message });
  if (!factura) return json(404, { ok: false, error: "factura_missing" });
  if (factura.direccion !== "emitida") {
    return json(400, { ok: false, error: "not_issued" });
  }
  if (factura.estado === "emitida" && factura.sif_external_id) {
    return json(200, {
      ok: true,
      sif_external_id: factura.sif_external_id,
      sif_status: factura.sif_status ?? "emitida",
    });
  }
  if (factura.estado === "anulada") {
    return json(409, { ok: false, error: "anulada" });
  }

  const { data: settings, error: setErr } = await userClient
    .from("tenant_settings")
    .select("emisor_nif, emisor_nombre, factura_serie, display_name")
    .eq("tenant_id", tenantId)
    .maybeSingle();
  if (setErr) return json(500, { ok: false, error: setErr.message });
  const emisorNif = `${settings?.emisor_nif ?? ""}`.trim().toUpperCase();
  if (!emisorNif) {
    return json(400, { ok: false, error: "emisor_nif_required" });
  }
  const emisorNombre = `${settings?.emisor_nombre ?? settings?.display_name ?? ""}`
    .trim();

  const vendor = (Deno.env.get("SIF_VENDOR") ?? "verifacti").trim()
    .toLowerCase();
  const apiUrl = (Deno.env.get("SIF_API_URL") ?? "").replace(/\/$/, "");
  const apiKey = Deno.env.get("SIF_API_KEY") ?? "";
  if (!apiUrl || !apiKey) {
    return json(501, { ok: false, error: "sif_not_configured" });
  }

  const canonical = {
    emisor_nif: emisorNif,
    emisor_nombre: emisorNombre,
    serie: `${factura.serie ?? settings?.factura_serie ?? "A"}`.trim() || "A",
    numero: `${factura.numero ?? ""}`.trim(),
    fecha: `${factura.fecha ?? ""}`.trim(),
    tipo_factura: "F1",
    descripcion: `${factura.concepto ?? ""}`.trim() || "Servicios",
    destinatario_nif: `${factura.destinatario_nif ?? ""}`.trim().toUpperCase(),
    destinatario_nombre: `${factura.destinatario_nombre ?? ""}`.trim(),
    base_cents: num(factura.base_cents),
    iva_cents: num(factura.iva_cents),
    iva_bps: num(factura.iva_bps) || 2100,
    total_cents: num(factura.total_cents),
  };
  if (!canonical.numero || !canonical.fecha) {
    return json(400, { ok: false, error: "numero_fecha_required" });
  }

  let sent: { url: string; payload: Record<string, unknown>; headers: Record<string, string> };
  try {
    sent = mapVendor(vendor, apiUrl, apiKey, canonical);
  } catch (e) {
    return json(400, { ok: false, error: `${e}` });
  }

  const res = await fetch(sent.url, {
    method: "POST",
    headers: sent.headers,
    body: JSON.stringify(sent.payload),
  });
  const text = await res.text();
  let parsed: Record<string, unknown> = {};
  try {
    parsed = text ? JSON.parse(text) as Record<string, unknown> : {};
  } catch {
    parsed = { raw: text.slice(0, 2000) };
  }

  const externalId = str(
    parsed.uuid ?? parsed.id ?? parsed.Id ?? parsed.sif_external_id,
  );
  const qr = str(
    parsed.qr ?? parsed.qr_image ?? parsed.url_qr ?? parsed.sif_qr_url,
  );
  const ok = res.ok;
  const status = ok ? (str(parsed.estado) || "pendiente") : "error";

  await userClient.from("facturas").update({
    estado: ok ? "emitida" : "error",
    sif_provider: vendor,
    sif_external_id: externalId || null,
    sif_status: status,
    sif_qr_url: qr || null,
    sif_error: ok ? null : (str(parsed.error) || text.slice(0, 500)),
  }).eq("id", facturaId).eq("tenant_id", tenantId);

  if (!ok) {
    return json(502, {
      ok: false,
      error: "sif_rejected",
      sif_status: status,
    });
  }
  return json(200, {
    ok: true,
    sif_external_id: externalId,
    sif_status: status,
    sif_qr_url: qr,
  });
});

function mapVendor(
  vendor: string,
  apiUrl: string,
  apiKey: string,
  c: {
    emisor_nif: string;
    emisor_nombre: string;
    serie: string;
    numero: string;
    fecha: string;
    tipo_factura: string;
    descripcion: string;
    destinatario_nif: string;
    destinatario_nombre: string;
    base_cents: number;
    iva_cents: number;
    iva_bps: number;
    total_cents: number;
  },
): { url: string; payload: Record<string, unknown>; headers: Record<string, string> } {
  const headers = {
    "Content-Type": "application/json",
    Authorization: `Bearer ${apiKey}`,
  };
  const tipo = (c.iva_bps / 100).toFixed(2);
  const base = euros(c.base_cents);
  const cuota = euros(c.iva_cents);
  const total = euros(c.total_cents);
  if (vendor === "verifactuapi") {
    return {
      url: `${apiUrl}/api/alta-registro-facturacion`,
      headers,
      payload: {
        IDEmisorFactura: c.emisor_nif,
        NumSerieFactura: `${c.serie}/${c.numero}`,
        FechaExpedicionFactura: c.fecha,
        TipoFactura: c.tipo_factura,
        DescripcionOperacion: c.descripcion,
        Destinatarios: [
          {
            NombreRazon: c.destinatario_nombre,
            NIF: c.destinatario_nif,
          },
        ],
        Desglose: [
          {
            Impuesto: 1,
            ClaveRegimen: 1,
            CalificacionOperacion: 1,
            TipoImpositivo: c.iva_bps / 100,
            BaseImponibleOImporteNoSujeto: c.base_cents / 100,
            CuotaRepercutida: c.iva_cents / 100,
          },
        ],
        CuotaTotal: c.iva_cents / 100,
        ImporteTotal: c.total_cents / 100,
      },
    };
  }
  // Default: Verifacti POST /verifactu/create (API key firmy, ne účet).
  return {
    url: `${apiUrl}/verifactu/create`,
    headers,
    payload: {
      serie: c.serie,
      numero: c.numero,
      fecha_expedicion: c.fecha,
      tipo_factura: c.tipo_factura,
      descripcion: c.descripcion,
      nif: c.destinatario_nif || undefined,
      nombre: c.destinatario_nombre || undefined,
      lineas: [
        {
          base_imponible: base,
          tipo_impositivo: tipo,
          cuota_repercutida: cuota,
        },
      ],
      importe_total: total,
    },
  };
}

function euros(cents: number): string {
  return (cents / 100).toFixed(2);
}
function num(v: unknown): number {
  if (typeof v === "number") return v;
  return parseInt(`${v ?? 0}`, 10) || 0;
}
function str(v: unknown): string {
  return `${v ?? ""}`.trim();
}
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
