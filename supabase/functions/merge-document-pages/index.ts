import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { PDFDocument } from "npm:pdf-lib@1.17.1";
import { createClient } from "npm:@supabase/supabase-js@2";

/**
 * 2–20 fotek téhož klienta → jedno PDF. Pořadí posílá gestor, ne AI.
 * Zdroje soft-delete. Extract classify na novém papíru. PDF se neřeže.
 */

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MAX_PAGES = 20;
const A4 = { width: 595, height: 842 };

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
    documento_ids?: unknown;
  };
  const tenantId = typeof body.tenant_id === "string" ? body.tenant_id.trim() : "";
  const clienteId = typeof body.cliente_id === "string"
    ? body.cliente_id.trim()
    : "";
  const ids = Array.isArray(body.documento_ids)
    ? body.documento_ids.map((x) => `${x ?? ""}`.trim()).filter(Boolean)
    : [];
  if (!tenantId || !clienteId || ids.length < 2) {
    return json(400, { ok: false, error: "need_photos" });
  }
  if (ids.length > MAX_PAGES) {
    return json(400, { ok: false, error: "too_many" });
  }
  const unique = new Set(ids);
  if (unique.size !== ids.length) {
    return json(400, { ok: false, error: "need_photos" });
  }

  const { data: allowed } = await userClient.rpc("can_access_tenant", {
    _tenant_id: tenantId,
  });
  if (allowed !== true) return json(403, { ok: false, error: "forbidden" });

  const { data: rows, error: selErr } = await userClient
    .from("documentos")
    .select(
      "id, tenant_id, cliente_id, storage_path, original_name, inmueble_id, tipo",
    )
    .in("id", ids)
    .eq("tenant_id", tenantId)
    .eq("cliente_id", clienteId)
    .is("deleted_at", null);
  if (selErr) return json(500, { ok: false, error: selErr.message });
  const byId = new Map(
    (rows ?? []).map((r) => [`${r.id}`, r as Record<string, unknown>]),
  );
  if (byId.size !== ids.length) {
    return json(400, { ok: false, error: "not_found" });
  }

  const pdf = await PDFDocument.create();
  for (const id of ids) {
    const row = byId.get(id)!;
    const path = `${row.storage_path ?? ""}`;
    const name = `${row.original_name ?? path}`;
    if (!isMergeImagePath(path, name)) {
      return json(400, { ok: false, error: "need_photos" });
    }
    const { data: file, error: dlErr } = await userClient.storage
      .from("documentos")
      .download(path);
    if (dlErr || !file) {
      return json(500, { ok: false, error: "download" });
    }
    const bytes = new Uint8Array(await file.arrayBuffer());
    try {
      await addImagePage(pdf, bytes);
    } catch (err) {
      console.warn("merge embed", name, err);
      return json(400, { ok: false, error: "need_photos" });
    }
  }

  const pdfBytes = await pdf.save();
  const hash = await sha256Hex(pdfBytes);
  const { data: dup } = await userClient
    .from("documentos")
    .select("id")
    .eq("tenant_id", tenantId)
    .eq("cliente_id", clienteId)
    .eq("content_sha256", hash)
    .is("deleted_at", null)
    .maybeSingle();
  if (dup) return json(409, { ok: false, error: "duplicate" });

  const firstName = `${byId.get(ids[0])?.original_name ?? "sken"}`;
  const originalName = mergePdfName(firstName);
  const storagePath = `${tenantId}/${clienteId}/stoh/${Date.now().toString(16)}_${
    ids[0].slice(0, 8)
  }_${safeName(originalName)}`;

  const { error: upErr } = await userClient.storage.from("documentos").upload(
    storagePath,
    pdfBytes,
    { contentType: "application/pdf", upsert: false },
  );
  if (upErr) return json(500, { ok: false, error: "upload" });

  const inmuebleIds = [
    ...new Set(
      ids.map((id) => `${byId.get(id)?.inmueble_id ?? ""}`.trim()).filter(
        (v) => v && v !== "null",
      ),
    ),
  ];
  const inmuebleId = inmuebleIds.length === 1 ? inmuebleIds[0] : null;

  const { data: inserted, error: insErr } = await userClient
    .from("documentos")
    .insert({
      tenant_id: tenantId,
      cliente_id: clienteId,
      tipo: "otro",
      storage_path: storagePath,
      original_name: originalName,
      created_by: userData.user.id,
      content_sha256: hash,
      inmueble_id: inmuebleId,
    })
    .select("id")
    .single();
  if (insErr || !inserted) {
    await userClient.storage.from("documentos").remove([storagePath]);
    return json(500, { ok: false, error: "db" });
  }

  const now = new Date().toISOString();
  await userClient
    .from("documentos")
    .update({ deleted_at: now, updated_at: now })
    .in("id", ids);

  const extractUrl = `${supabaseUrl()}/functions/v1/extract-document`;
  try {
    await fetch(extractUrl, {
      method: "POST",
      headers: {
        Authorization: authHeader,
        apikey: supabaseAnonKey(),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        tenant_id: tenantId,
        cliente_id: clienteId,
        storage_path: storagePath,
        mime: "application/pdf",
        classify: true,
      }),
    });
  } catch (err) {
    console.warn("merge extract", err);
  }

  return json(200, {
    ok: true,
    documento_id: inserted.id,
    storage_path: storagePath,
  });
});

function isMergeImagePath(path: string, name: string): boolean {
  const s = `${name} ${path}`.toLowerCase();
  return /\.(jpe?g|png)(\b|$)/.test(s);
}

function safeName(name: string): string {
  const s = name.replace(/[^A-Za-z0-9._-]/g, "_");
  return s || "sken.pdf";
}

function mergePdfName(first: string): string {
  const base = first.replace(/\.[^.]+$/, "") || "sken";
  return `${base}_merged.pdf`;
}

async function addImagePage(pdf: PDFDocument, bytes: Uint8Array) {
  const jpeg = bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 &&
    bytes[2] === 0xff;
  const png = bytes.length >= 4 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
    bytes[2] === 0x4e && bytes[3] === 0x47;
  if (!jpeg && !png) throw new Error("not image");
  const img = jpeg ? await pdf.embedJpg(bytes) : await pdf.embedPng(bytes);
  const scale = Math.min(A4.width / img.width, A4.height / img.height);
  const w = img.width * scale;
  const h = img.height * scale;
  const page = pdf.addPage([A4.width, A4.height]);
  page.drawImage(img, {
    x: (A4.width - w) / 2,
    y: (A4.height - h) / 2,
    width: w,
    height: h,
  });
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) =>
    b.toString(16).padStart(2, "0")
  ).join("");
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
