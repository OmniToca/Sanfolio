import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { extractPdfPages, pdfTextUsable } from "../_shared/pdf_extract.ts";
import { embedTexts, replaceDocumentoChunks } from "../_shared/embed_chunks.ts";

/**
 * Fotka / PDF → návrh do ai_drafts. body_text na documentos.
 * Jistý classify zapíše album (place_documento_ai), ne pole desky.
 * Vzory: podobné zařazené papíry téhož tenantu, ne dotrénování modelu.
 * HTTP vrátí pending hned; LLM doběhne na pozadí (waitUntil). Guardar polí je gestor.
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
    classify?: unknown;
  };
  const tenantId = typeof body.tenant_id === "string" ? body.tenant_id.trim() : "";
  const clienteId = typeof body.cliente_id === "string" ? body.cliente_id.trim() : "";
  const storagePath = typeof body.storage_path === "string"
    ? body.storage_path.trim()
    : "";
  const mime = typeof body.mime === "string" ? body.mime.trim() : "";
  const docTipo = typeof body.doc_tipo === "string" ? body.doc_tipo.trim() : "";
  const classify = body.classify === true || body.classify === "true";
  const bloqueKey = typeof body.bloque_key === "string" && body.bloque_key.trim()
    ? body.bloque_key.trim()
    : classify
    ? ""
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
      bloque_key: bloqueKey || null,
      fields: { extract_status: "pending" },
      storage_path: storagePath,
      expires_at: null,
    })
    .select("id")
    .single();
  if (insErr || !draft) {
    return json(500, { ok: false, error: insErr?.message ?? "draft insert failed" });
  }

  const { data: docRow } = await userClient
    .from("documentos")
    .select("id")
    .eq("tenant_id", tenantId)
    .eq("storage_path", storagePath)
    .is("deleted_at", null)
    .maybeSingle();
  if (docRow && typeof docRow.id === "string") {
    await userClient
      .from("ai_drafts")
      .update({ documento_id: docRow.id })
      .eq("id", draft.id);
  }

  const work = finishExtract({
    userClient,
    userId: userData.user.id,
    tenantId,
    clienteId,
    draftId: `${draft.id}`,
    storagePath,
    mime,
    docTipo,
    bloqueKey,
    classify,
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
  clienteId: string;
  draftId: string;
  storagePath: string;
  mime: string;
    docTipo: string;
    bloqueKey: string;
    classify: boolean;
  }) {
  try {
    const hint = await loadClienteHint(args.userClient, args.clienteId);
    const docTipo = guessTipoFromPath(args.storagePath, args.docTipo);
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
    const identity = docTipo === "dni_nie" || docTipo === "pasaporte";
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
        docTipo,
        isPdf,
        args.classify,
      );
      if (vision) {
        const body = fields.body_text;
        fields = { ...fields, ...sanitizeFields(vision) };
        if (body && !fields.body_text) fields.body_text = body;
      }
    }
    let officeExamples: OfficePaperExample[] = [];
    if (apiKey && fields.body_text && args.classify) {
      try {
        officeExamples = await loadOfficePaperExamples({
          userClient: args.userClient,
          tenantId: args.tenantId,
          storagePath: args.storagePath,
          body: fields.body_text,
          apiKey,
        });
      } catch (err) {
        console.warn("extract-document: office examples", err);
      }
    }
    const officeHint = officeExamplesPrompt(officeExamples);
    if (apiKey && fields.body_text && !identity) {
      const llm = await llmExtractFromText(
        apiKey,
        fields.body_text,
        docTipo,
        hint,
        args.classify,
        officeHint,
      );
      if (llm) {
        const body = fields.body_text;
        fields = { ...fields, ...sanitizeFields(llm) };
        fields.body_text = body;
      }
    }
    if (fields.body_text) {
      fields = alignDeedFields(fields, fields.body_text, hint);
    }
    if (args.classify) {
      const guess = classifyStohPaper(
        args.storagePath,
        fields.body_text ?? "",
        fields,
        officeClassifyConsensus(officeExamples),
      );
      if (guess.bloque) fields.proposed_bloque_key = guess.bloque;
      if (guess.tipo) fields.proposed_tipo = guess.tipo;
      if (guess.bloque) {
        await args.userClient.from("ai_drafts").update({
          bloque_key: guess.bloque,
          updated_at: new Date().toISOString(),
        }).eq("id", args.draftId);
      }
    }
    const extracted = Object.keys(fields).length > 0 &&
      !(Object.keys(fields).length === 1 && fields.extract_status);
    await markDraft(
      args.userClient,
      args.draftId,
      extracted ? fields : { extract_status: "failed" },
    );
    if (extracted) {
      try {
        await persistLibraryExtract(args, fields);
      } catch (err) {
        console.warn("extract-document: library persist", err);
      }
    }
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

async function persistLibraryExtract(
  args: {
    userClient: ReturnType<typeof createClient>;
    tenantId: string;
    clienteId: string;
    draftId: string;
    storagePath: string;
    classify: boolean;
  },
  fields: Record<string, string>,
) {
  const { data: draft } = await args.userClient
    .from("ai_drafts")
    .select("documento_id")
    .eq("id", args.draftId)
    .maybeSingle();
  let docId = typeof draft?.documento_id === "string" ? draft.documento_id : "";
  if (!docId) {
    const { data: docRow } = await args.userClient
      .from("documentos")
      .select("id")
      .eq("tenant_id", args.tenantId)
      .eq("storage_path", args.storagePath)
      .is("deleted_at", null)
      .maybeSingle();
    docId = typeof docRow?.id === "string" ? docRow.id : "";
  }
  if (!docId) return;

  const body = (fields.body_text ?? "").trim();
  const guessBloque = (fields.proposed_bloque_key ?? "").trim();
  const guessTipo = (fields.proposed_tipo ?? "").trim() || "other";
  const patch: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  };
  if (body) patch.body_text = body;
  if (guessTipo && guessTipo !== "other") patch.tipo = guessTipo;
  await args.userClient.from("documentos").update(patch).eq("id", docId);

  if (body) {
    const apiKey = Deno.env.get("OPENAI_API_KEY")?.trim();
    if (apiKey) {
      try {
        await replaceDocumentoChunks({
          userClient: args.userClient,
          documentoId: docId,
          body,
          apiKey,
        });
      } catch (err) {
        console.warn("extract-document: embed chunks", err);
      }
    }
  }

  if (!args.classify || !STOH_BLOQUES.has(guessBloque)) return;
  if (PERSON_BLOQUES.has(guessBloque)) return;
  const fileName = (args.storagePath.split("/").pop() ?? "").toLowerCase();
  if (
    guessBloque === "escritura" &&
    /factura|invoice|recibo|p[oó]der|apoderad/.test(fileName)
  ) {
    return;
  }

  const found = await findBloqueForGuess(
    args.userClient,
    args.clienteId,
    guessBloque,
    fields,
  );
  if (found.inmuebleId) {
    await args.userClient.from("documentos").update({
      inmueble_id: found.inmuebleId,
      updated_at: new Date().toISOString(),
    }).eq("id", docId);
  }
  if (!found.bloqueId) return;
  await args.userClient.rpc("place_documento_ai", {
    p_documento_id: docId,
    p_bloque_id: found.bloqueId,
    p_tipo: guessTipo,
  });
}

const PERSON_BLOQUES = new Set(["cliente_snapshot", "nie_tramite", "poder"]);
const FINCA_BLOQUES = new Set([
  "escritura",
  "agua",
  "luz",
  "gaz",
  "comunidad",
  "suma",
  "plusvalia",
  "seguro",
  "alarma",
]);

async function findBloqueForGuess(
  userClient: ReturnType<typeof createClient>,
  clienteId: string,
  templateKey: string,
  fields: Record<string, string>,
): Promise<{ bloqueId: string | null; inmuebleId: string }> {
  const { data: inms } = await userClient
    .from("inmuebles")
    .select("id, direccion, referencia_catastral")
    .eq("cliente_id", clienteId)
    .is("deleted_at", null);
  const properties = (inms ?? []) as Array<{
    id: string;
    direccion?: string;
    referencia_catastral?: string;
  }>;
  const guessed = guessInmueble(templateKey, properties, fields);

  const { data: rows } = await userClient
    .from("bloques")
    .select("id, expedientes!inner(cliente_id, inmueble_id, deleted_at)")
    .eq("template_key", templateKey)
    .eq("expedientes.cliente_id", clienteId)
    .is("deleted_at", null)
    .is("expedientes.deleted_at", null);
  const matches = (rows ?? []).filter((raw) => {
    const exp = raw.expedientes as {
      inmueble_id?: string | null;
    } | Array<{ inmueble_id?: string | null }>;
    const one = Array.isArray(exp) ? exp[0] : exp;
    if (!guessed) return true;
    return (one?.inmueble_id ?? "") === guessed;
  });
  const bloqueId = matches.length === 1 && typeof matches[0].id === "string"
    ? matches[0].id
    : null;
  return { bloqueId, inmuebleId: guessed };
}

function guessInmueble(
  bloque: string,
  properties: Array<{
    id: string;
    direccion?: string;
    referencia_catastral?: string;
  }>,
  fields: Record<string, string>,
): string {
  if (!FINCA_BLOQUES.has(bloque) || properties.length === 0) return "";
  const addr = (fields["fields.address"] ?? "").trim().toLowerCase();
  const cat = (fields["fields.cadastral"] ?? "").trim().toLowerCase().replaceAll(" ", "");
  const hits = properties.filter((p) => {
    const d = (p.direccion ?? "").trim().toLowerCase();
    const c = (p.referencia_catastral ?? "").trim().toLowerCase().replaceAll(" ", "");
    const byCat = cat.length > 0 && c.length > 0 && (c === cat || cat.includes(c) || c.includes(cat));
    const byAddr = addr.length > 0 && d.length > 0 && (addr.includes(d) || d.includes(addr));
    return byCat || byAddr;
  });
  if (hits.length === 1) return hits[0].id;
  if (properties.length === 1) {
    const paperHasSignal = cat.length > 0 || addr.length > 0;
    if (paperHasSignal) return "";
    return properties[0].id;
  }
  return "";
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
  base: "fields.base",
  iva: "fields.iva",
  ivaRate: "fields.ivaRate",
  due: "fields.due",
  concept: "fields.concept",
  supplierNif: "fields.supplierNif",
  notary: "fields.notary",
  protocol: "fields.protocol",
  date: "fields.date",
  company: "fields.company",
  policy: "fields.policy",
  attorney: "fields.attorney",
  seller: "fields.seller",
  sellerNie: "fields.sellerNie",
  sellers: "fields.sellers",
  buyers: "fields.buyers",
  lawyer: "fields.lawyer",
  address: "fields.address",
  cadastral: "fields.cadastral",
  parcela: "fields.parcela",
  registry: "fields.registry",
  salePrice: "fields.salePrice",
  referenceValue: "fields.referenceValue",
  sumaId: "fields.sumaId",
  directDebit: "fields.directDebit",
  body_text: "body_text",
};

const EXTRACT_KEY_LIST = Object.keys(FIELD_MAP).join(",");

function extractSystemPrompt(
  docTipo: string,
  includeBody: boolean,
  classify = false,
): string {
  return (
    `Extract fields from a Spanish gestoría document (declared type: ${docTipo || "unknown"}). ` +
    "It may be a factura even if the type says contrato. Keep official terms (NIE, CUPS, escritura). " +
    `Return JSON only with keys you actually see: ${EXTRACT_KEY_LIST}` +
    (classify
      ? ", proposedBloque, proposedTipo"
      : "") +
    ". " +
    "Nº de contrato / póliza → contractNo. Nº de cliente → clientNo. Nº factura → invoiceNo. " +
    "Periodo de facturación → periodFrom and periodTo (YYYY-MM-DD), not period (period is IBI year only). " +
    "IBI / SUMA recibo: period = ejercicio year (2024), never the payment window. " +
    "Identificación SUMA / nº objeto → sumaId (not recibo number, not NIE). " +
    "Domiciliado sí → directDebit true, no or aplazamiento → false. " +
    "address = the inmueble (objeto / finca), never the SUMA office letterhead " +
    "(C/ Dr. Luis Rivera, Guardamar) and never a seller's professional domicilio. " +
    "Agua (Hidraqua, Aqualia, Canal…): billing period is usually ~3 months (trimestral / TRIMESTRAL). " +
    "Use that full Periodo de facturación, never a single month from the consumo chart or lectura table. " +
    "Fecha de emisión → issued. Importe total → amount as 188.85 (dot, no currency). " +
    "factura_recibida / supplier invoice: emisor → company + supplierNif (CIF/NIF). " +
    "Do not put the supplier tax id into nie. Titular/cliente → holder/nombre. " +
    "Base imponible → base, IVA cuota → iva, IVA % → ivaRate (21), vencimiento → due, " +
    "concepto → concept. " +
    "Consumo kWh or m³ → consumption. Compañía / comercializadora → company. Titular → holder. " +
    "póliza de seguro / prima: importe or prima anual → amount. Periodo de cobertura → periodFrom and periodTo. " +
    "Dates YYYY-MM-DD. Omit unknown. Do not invent. " +
    "Escritura de compraventa: list ALL sellers in sellers and ALL real buyers in buyers as 'NAME (NIE); NAME (NIE)'. " +
    "A representative (en nombre y representación) is attorney, not a buyer. Interpreter is not a party. " +
    "A town in the address (Rychnov nad Kněžnou, Nad Kneznou) is not a surname. Nationality (británica, checa) is not a name. " +
    "nombre and nie = the office client if they appear among the parties. " +
    "salePrice = precio de esta compraventa only, not valor de referencia, not hipoteca, not partial transfers. " +
    "referenceValue = valor de referencia catastral. lawyer = despacho/abogado. " +
    "parcela, registry (Registro de la Propiedad + finca), cadastral, address of the URBANA. " +
    "protocol is the number at the very top (DOS MIL CIENTO DIECISÉIS = 2116), not a later year or poder. " +
    "Do not put passport numbers into tel." +
    (classify
      ? " proposedBloque = one of cliente_snapshot,escritura,agua,luz,gaz,comunidad,suma,plusvalia,seguro,alarma,nie_tramite,poder (omit if unsure). " +
        "proposedTipo = dni_nie,pasaporte,copia_escritura,contrato_agua,factura_agua,recibo_agua,contrato_luz,factura_luz,contrato_gaz,factura_gaz,certificado_comunidad,recibo_ibi,declaracion_plusvalia,certificado_catastral,poliza_seguro,contrato_alarma,copia_poder,other (omit if unsure). " +
        "Title and first page of the PDF first; ignore scan_01.pdf / IMG_1234. " +
        "Poder/apoderado in the filename → poder, never escritura. FACTURA/invoice/recibo in the filename → not escritura even if a clause mentions notario. " +
        "A NIE on a deed is not cliente_snapshot. ESCRITURA DE COMPRAVENTA / AMPLIACIÓN DE OBRA / Ante mí, Notario → escritura. " +
        "CERTIFICACIÓN CATASTRAL DE VALOR DE REFERENCIA → plusvalia (certificado_catastral), not IBI and not the deed. " +
        "Hidraqua/Aqualia → agua. CUPS/kWh/Iberdrola/Gana Energía → luz. DNI/NIE card photo → cliente_snapshot. Omit proposedBloque if unsure."
      : "") +
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
    out[dest] = src === "nie" || src === "sellerNie"
      ? v.toUpperCase()
      : src === "email"
      ? v.toLowerCase()
      : v;
  }
  return out;
}

function fieldsFromText(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  const nie = text.match(/\b(?:[XYZ]\s*-?\s*[0-9*]{7}\s*-?\s*[A-Z]|[0-9*]{8}[A-Z])\b/i);
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
    if (key === "fields.nie" || key === "fields.sellerNie") {
      if (looksLikeNie(v)) out[key] = v.toUpperCase().replace(/\s/g, "");
      continue;
    }
    if (key === "fields.supplierNif") {
      const compact = v.toUpperCase().replace(/[\s\-\./]/g, "");
      if (compact.length >= 8 && compact.length <= 12) out[key] = compact;
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
    const long = key === "fields.buyers" ||
      key === "fields.sellers" ||
      key === "fields.address" ||
      key === "fields.registry" ||
      key === "fields.lawyer" ||
      key === "fields.attorney";
    if (v.length <= (long ? 2000 : 200)) out[key] = v;
  }
  return out;
}

async function llmExtractFromText(
  apiKey: string,
  text: string,
  docTipo: string,
  hint: { nombre: string; nie: string },
  classify = false,
  officeHint = "",
): Promise<Record<string, string> | null> {
  const clipped = escrituraLlmFocus(text).slice(0, 24000);
  const who = [
    hint.nombre ? `Office client name: ${hint.nombre}.` : "",
    hint.nie ? `Office client NIE: ${hint.nie}.` : "",
  ].filter(Boolean).join(" ");
  const userText = [officeHint, who, clipped].filter(Boolean).join("\n\n");
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
        { role: "system", content: extractSystemPrompt(docTipo, false, classify) },
        {
          role: "user",
          content: userText,
        },
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
    const mapped = mapLlmFields(parsed);
    const bloque = str(parsed.proposedBloque ?? parsed.proposed_bloque_key);
    const tipo = str(parsed.proposedTipo ?? parsed.proposed_tipo);
    if (bloque) mapped.proposed_bloque_key = bloque;
    if (tipo) mapped.proposed_tipo = tipo;
    return mapped;
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
  classify = false,
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
          content: extractSystemPrompt(docTipo, true, classify),
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

function guessTipoFromPath(path: string, declared: string): string {
  if (declared && declared !== "other") return declared;
  const name = path.split("/").pop() ?? "";
  if (/escritur|compravent|smlouv|notari|\besc\b/i.test(name)) return "copia_escritura";
  return declared;
}

const STOH_BLOQUES = new Set([
  "cliente_snapshot",
  "escritura",
  "agua",
  "luz",
  "gaz",
  "comunidad",
  "suma",
  "plusvalia",
  "seguro",
  "alarma",
  "nie_tramite",
  "poder",
]);

const PODER_NAME = /p[oó]der|apoderad/;
const FACTURA_NAME = /factura|invoice|recibo/;
const ESCRITURA_NAME = /escritur|compravent|\besc\b/;
const LUZ_HINT = /iberdrola|endesa|holaluz|gana energ|\bcups\b|\bkwh\b|\bluz\b/;
const BODY_HEAD_CHARS = 4000;

function stohBodyHead(body: string): string {
  const t = body.trim();
  return (t.length <= BODY_HEAD_CHARS ? t : t.slice(0, BODY_HEAD_CHARS)).toLowerCase();
}

function classifyBodyHead(
  head: string,
  invoiceName: boolean,
): { bloque: string; tipo: string } | null {
  if (
    /escritur[ae] de p[oó]der|p[oó]der notarial|poder especial|poder general/.test(head) &&
    !/escritur[ae] de compravent/.test(head)
  ) {
    return { bloque: "poder", tipo: "copia_poder" };
  }
  if (
    !invoiceName &&
    (/escritur[ae] de compravent|escritur[ae] de ampliaci|obra nueva|declaraci[oó]n de obra|escritur[ae] p[uú]blica/.test(head) ||
      (/escritur[ae] de/.test(head) && !/p[oó]der/.test(head)) ||
      (/ante m[ií]/.test(head) && /notari/.test(head)))
  ) {
    return { bloque: "escritura", tipo: "copia_escritura" };
  }
  if (
    /documento nacional de identidad|n[uú]mero de identidad de extranjero|tarjeta de (residencia|identidad)/.test(head) &&
    !/escritur/.test(head)
  ) {
    return { bloque: "cliente_snapshot", tipo: "dni_nie" };
  }
  if (
    /valor de referenc|certificaci[oó]n catastral/.test(head) &&
    !/escritur[ae] de/.test(head)
  ) {
    return { bloque: "plusvalia", tipo: "certificado_catastral" };
  }
  return null;
}

type OfficePaperExample = {
  bloqueKey: string;
  tipo: string;
  source: string;
  title: string;
  caption: string;
  filledKeys: string[];
  dist: number;
};

const OFFICE_MAX_DIST = 0.45;
const OFFICE_TIGHT_DIST = 0.28;
const OFFICE_NIE = /\b(?:[XYZ]\s*-?\s*[0-9*]{7}\s*-?\s*[A-Z]|[0-9*]{8}[A-Z])\b/gi;
const OFFICE_EMAIL = /[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/gi;
const OFFICE_TEL = /\+?\d[\d \-]{7,14}\d/g;

function redactOfficeExampleText(raw: string): string {
  let t = raw.trim().replace(/\s+/g, " ");
  t = t.replace(OFFICE_NIE, "[NIE]");
  t = t.replace(OFFICE_EMAIL, "[email]");
  t = t.replace(OFFICE_TEL, "[tel]");
  return t.length > 120 ? t.slice(0, 120) : t;
}

function officeClassifyConsensus(
  raw: OfficePaperExample[],
): { bloque: string; tipo: string } | null {
  const close = raw.filter((e) =>
    e.dist <= OFFICE_MAX_DIST && STOH_BLOQUES.has(e.bloqueKey)
  );
  if (close.length === 0) return null;
  const byBloque = new Map<string, OfficePaperExample[]>();
  for (const e of close) {
    const list = byBloque.get(e.bloqueKey) ?? [];
    list.push(e);
    byBloque.set(e.bloqueKey, list);
  }
  let bestKey = "";
  let bestCount = 0;
  let bestDist = 99;
  for (const [key, list] of byBloque) {
    const avg = list.reduce((s, x) => s + x.dist, 0) / list.length;
    if (list.length > bestCount || (list.length === bestCount && avg < bestDist)) {
      bestKey = key;
      bestCount = list.length;
      bestDist = avg;
    }
  }
  let winners: OfficePaperExample[];
  if (bestCount >= 2) {
    winners = byBloque.get(bestKey) ?? [];
  } else {
    const only = close[0];
    if (only.source !== "human" || only.dist > OFFICE_TIGHT_DIST) return null;
    winners = [only];
    bestKey = only.bloqueKey;
  }
  const tipos = new Map<string, number>();
  for (const e of winners) {
    const t = (e.tipo ?? "").trim();
    if (!t || t === "other") continue;
    tipos.set(t, (tipos.get(t) ?? 0) + 1);
  }
  let tipo = "other";
  let tipoN = 0;
  for (const [t, n] of tipos) {
    if (n > tipoN) {
      tipo = t;
      tipoN = n;
    }
  }
  return { bloque: bestKey, tipo };
}

function officeExamplesPrompt(raw: OfficePaperExample[]): string {
  const lines: string[] = [];
  for (const e of raw) {
    if (e.dist > OFFICE_MAX_DIST || !STOH_BLOQUES.has(e.bloqueKey)) continue;
    if (lines.length >= 5) break;
    const keys = e.filledKeys.filter((k) => k.startsWith("fields.")).slice(0, 8)
      .join(",");
    const title = redactOfficeExampleText(e.title);
    const caption = redactOfficeExampleText(e.caption);
    const n = lines.length + 1;
    lines.push(
      `${n}. album=${e.bloqueKey} tipo=${e.tipo} source=${e.source}` +
        (keys ? ` keys=${keys}` : "") +
        (title ? ` title=${title}` : "") +
        (caption ? ` caption=${caption}` : ""),
    );
  }
  if (lines.length === 0) return "";
  return "This office already filed similar papers (same tenant, not this file). " +
    "Follow their album and which fields they kept. Do not copy names or NIE. " +
    "If they agree, proposedBloque/proposedTipo should match. " +
    "IBI period is the year; address is the finca, never the SUMA office.\n" +
    lines.join("\n");
}

async function loadOfficePaperExamples(args: {
  userClient: ReturnType<typeof createClient>;
  tenantId: string;
  storagePath: string;
  body: string;
  apiKey: string;
}): Promise<OfficePaperExample[]> {
  const head = args.body.trim().slice(0, 1200);
  if (head.length < 40) return [];
  const [vector] = await embedTexts(args.apiKey, [head]);
  if (!vector || vector.length !== 1536) return [];
  const { data: docRow } = await args.userClient
    .from("documentos")
    .select("id")
    .eq("tenant_id", args.tenantId)
    .eq("storage_path", args.storagePath)
    .is("deleted_at", null)
    .maybeSingle();
  const excludeId = typeof docRow?.id === "string" ? docRow.id : null;
  const { data, error } = await args.userClient.rpc("similar_placed_papers", {
    p_tenant_id: args.tenantId,
    p_query_embedding: vector,
    p_exclude_documento_id: excludeId,
    p_limit: 5,
  });
  if (error) {
    console.warn("extract-document: similar_placed_papers", error.message);
    return [];
  }
  const items = (data as { items?: unknown } | null)?.items;
  if (!Array.isArray(items)) return [];
  const out: OfficePaperExample[] = [];
  for (const raw of items) {
    if (!raw || typeof raw !== "object") continue;
    const row = raw as Record<string, unknown>;
    const albums = Array.isArray(row.albums) ? row.albums : [];
    const bloque = typeof albums[0] === "string" ? albums[0] : "";
    const keys = Array.isArray(row.filled_keys)
      ? row.filled_keys.filter((k): k is string => typeof k === "string")
      : [];
    const dist = typeof row.dist === "number"
      ? row.dist
      : Number(row.dist ?? 1);
    out.push({
      bloqueKey: bloque,
      tipo: typeof row.tipo === "string" ? row.tipo : "other",
      source: row.source === "human" ? "human" : "ai",
      title: typeof row.title === "string" ? row.title : "",
      caption: typeof row.caption === "string" ? row.caption : "",
      filledKeys: keys,
      dist: Number.isFinite(dist) ? dist : 1,
    });
  }
  return out;
}

/// Stejné pořadí jako Flutter `classifyStohPaper`. První strana PDF, ne scan_01.
/// Název Poder/FACTURA je jen veto. Vzory kanceláře až po titulku, před LLM.
function classifyStohPaper(
  path: string,
  bodyText: string,
  fields: Record<string, string>,
  office?: { bloque: string; tipo: string } | null,
): { bloque: string; tipo: string } {
  const name = (path.split("/").pop() ?? "").toLowerCase();
  const head = stohBodyHead(bodyText);
  const hay = `${name}\n${bodyText.toLowerCase()}`;
  const cups = (fields["fields.cups"] ?? "").trim();
  const company = (fields["fields.company"] ?? "").toLowerCase();
  const invoiceName = FACTURA_NAME.test(name);

  if (PODER_NAME.test(name)) {
    return { bloque: "poder", tipo: "copia_poder" };
  }

  const fromHead = classifyBodyHead(head, invoiceName);
  if (fromHead) return fromHead;

  if (
    office?.bloque &&
    STOH_BLOQUES.has(office.bloque) &&
    !(office.bloque === "escritura" && invoiceName)
  ) {
    return {
      bloque: office.bloque,
      tipo: office.tipo || "other",
    };
  }

  const fromLlmBloque = STOH_BLOQUES.has(fields.proposed_bloque_key ?? "")
    ? fields.proposed_bloque_key!
    : "";
  const llmEscrituraOnInvoice = fromLlmBloque === "escritura" && invoiceName;
  const llmIdentityOnDeed = fromLlmBloque === "cliente_snapshot" &&
    head.length > 0 &&
    /escritur|compravent|notari/.test(head);
  if (fromLlmBloque && !llmEscrituraOnInvoice && !llmIdentityOnDeed) {
    return {
      bloque: fromLlmBloque,
      tipo: fields.proposed_tipo || "other",
    };
  }

  if (/pasaport|passport/.test(name)) {
    return { bloque: "cliente_snapshot", tipo: "pasaporte" };
  }
  if (/\bdni\b|\bnie\b/.test(name) && !ESCRITURA_NAME.test(name) && !invoiceName) {
    return { bloque: "cliente_snapshot", tipo: "dni_nie" };
  }
  if (ESCRITURA_NAME.test(name) && !invoiceName) {
    return { bloque: "escritura", tipo: "copia_escritura" };
  }
  if (/valor de referenc/.test(name)) {
    return { bloque: "plusvalia", tipo: "certificado_catastral" };
  }

  if (/plusval/.test(hay)) {
    return { bloque: "plusvalia", tipo: "declaracion_plusvalia" };
  }
  if (/\bibi\b|\bsuma\b/.test(hay) && !/escritur|compravent/.test(head)) {
    return { bloque: "suma", tipo: "recibo_ibi" };
  }
  if (/comunidad|administrador de fincas/.test(hay) && !/escritur/.test(head)) {
    return { bloque: "comunidad", tipo: "certificado_comunidad" };
  }
  if (/p[oó]liza|seguro/.test(hay) && !invoiceName) {
    return { bloque: "seguro", tipo: "poliza_seguro" };
  }
  if (/alarma/.test(hay) && !/escritur/.test(head)) {
    return { bloque: "alarma", tipo: "contrato_alarma" };
  }

  const aguaCo = /hidraqua|aqualia|\bagua\b|canal de isabel/;
  const gazHint = /\bgaz\b|\bgas natural\b|\bgas\b/;
  const looksFactura = FACTURA_NAME.test(hay);
  const looksContrato = /contrato/.test(hay);
  if (aguaCo.test(hay) || aguaCo.test(company)) {
    return {
      bloque: "agua",
      tipo: looksContrato && !looksFactura ? "contrato_agua" : "factura_agua",
    };
  }
  if (cups || LUZ_HINT.test(hay) || LUZ_HINT.test(company)) {
    const gazOnly = gazHint.test(hay) && !/\bkwh\b|\bluz\b|electric/.test(hay);
    if (gazOnly) {
      return {
        bloque: "gaz",
        tipo: looksContrato && !looksFactura ? "contrato_gaz" : "factura_gaz",
      };
    }
    return {
      bloque: "luz",
      tipo: looksContrato && !looksFactura ? "contrato_luz" : "factura_luz",
    };
  }
  if (gazHint.test(hay) || gazHint.test(company)) {
    return {
      bloque: "gaz",
      tipo: looksContrato && !looksFactura ? "contrato_gaz" : "factura_gaz",
    };
  }
  return { bloque: "", tipo: "other" };
}

async function loadClienteHint(
  userClient: ReturnType<typeof createClient>,
  clienteId: string,
): Promise<{ nombre: string; nie: string }> {
  const { data: cli } = await userClient
    .from("clientes")
    .select("nombre, apellidos")
    .eq("id", clienteId)
    .maybeSingle();
  const nombre = [cli?.nombre, cli?.apellidos]
    .map((x) => `${x ?? ""}`.trim())
    .filter(Boolean)
    .join(" ");
  const { data: ids } = await userClient
    .from("client_identifiers")
    .select("value_raw")
    .eq("cliente_id", clienteId)
    .is("deleted_at", null)
    .limit(4);
  let nie = "";
  for (const row of ids ?? []) {
    const v = `${(row as { value_raw?: string }).value_raw ?? ""}`;
    if (looksLikeNie(v)) {
      nie = v;
      break;
    }
  }
  return { nombre, nie };
}

function looksLikeEscrituraText(text: string): boolean {
  const t = text.toLowerCase();
  const deed = t.includes("escritura") ||
    t.includes("compraventa") ||
    t.includes("notario") ||
    t.includes("comparecen");
  const parties = t.includes("vender") ||
    t.includes("vendedor") ||
    t.includes("comprar") ||
    t.includes("comprador");
  return deed && parties;
}

function normalizeNie(raw: string): string {
  return raw.toUpperCase().replace(/[\s\-\./]/g, "");
}

type DeedPerson = { nie: string; name: string; index: number };

const deedNieRe = /\b([XYZ])\s*-?\s*(\d{7})\s*-?\s*([A-Z])\b/gi;
const dNameRe =
  /(?:^|[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ])(?:D[ªº]\.?|D\.|Doña|Don)\s+([A-ZÁÉÍÓÚÜÑ][A-ZÁÉÍÓÚÜÑa-záéíóúüñ.\-\s]{2,80}?)(?:,|\n|nacida|nacido|mayor|con |de soltera)/gi;

function tidyName(raw: string): string {
  return raw.replace(/\s+/g, " ").trim();
}

function looksLikeDeedPersonName(raw: string): boolean {
  const parts = raw.trim().split(/\s+/).filter((w) => w.length >= 2);
  return parts.length >= 2;
}

function deedPeople(text: string): DeedPerson[] {
  const out: DeedPerson[] = [];
  const re = new RegExp(deedNieRe.source, "gi");
  let m: RegExpExecArray | null;
  while ((m = re.exec(text))) {
    const nie = `${m[1]}${m[2]}${m[3]}`.toUpperCase();
    if (!looksLikeNie(nie)) continue;
    const from = Math.max(0, m.index - 800);
    const window = text.slice(from, m.index);
    let name = "";
    const names = new RegExp(dNameRe.source, "gi");
    let n: RegExpExecArray | null;
    while ((n = names.exec(window))) {
      const cand = tidyName(n[1] ?? "");
      if (looksLikeDeedPersonName(cand)) name = cand;
    }
    out.push({ nie, name, index: m.index });
  }
  return pairRespectivamente(out, text);
}

function pairRespectivamente(people: DeedPerson[], text: string): DeedPerson[] {
  if (!people.length) return people;
  const byNie = new Map(people.map((p) => [p.nie, p]));
  const resp = /respectivamente/gi;
  let m: RegExpExecArray | null;
  while ((m = resp.exec(text))) {
    const from = Math.max(0, m.index - 900);
    const window = text.slice(from, m.index + m[0].length);
    const names: string[] = [];
    const nameRe = new RegExp(dNameRe.source, "gi");
    let n: RegExpExecArray | null;
    while ((n = nameRe.exec(window))) {
      const cand = tidyName(n[1] ?? "");
      if (looksLikeDeedPersonName(cand)) names.push(cand);
    }
    const nies: string[] = [];
    const nieRe = new RegExp(deedNieRe.source, "gi");
    let k: RegExpExecArray | null;
    while ((k = nieRe.exec(window))) {
      nies.push(`${k[1]}${k[2]}${k[3]}`.toUpperCase());
    }
    const take = Math.min(names.length, nies.length);
    if (take < 2) continue;
    const nameSlice = names.slice(names.length - take);
    const nieSlice = nies.slice(nies.length - take);
    for (let i = 0; i < take; i++) {
      const prev = byNie.get(nieSlice[i]);
      if (!prev) continue;
      byNie.set(nieSlice[i], { ...prev, name: nameSlice[i] });
    }
  }
  return people.map((p) => byNie.get(p.nie) ?? p);
}

function partyLabel(p: DeedPerson): string {
  return p.name ? `${p.name} (${p.nie})` : p.nie;
}

function uniqueNie(people: DeedPerson[]): DeedPerson[] {
  const seen = new Set<string>();
  return people.filter((p) => {
    if (seen.has(p.nie)) return false;
    seen.add(p.nie);
    return true;
  });
}

function indexOfAny(lower: string, marks: string[]): number {
  let best = -1;
  for (const m of marks) {
    const i = lower.indexOf(m);
    if (i < 0) continue;
    if (best < 0 || i < best) best = i;
  }
  return best;
}

function firstEuro(text: string, at: number, window: number): string | null {
  const slice = text.slice(at, Math.min(text.length, at + window));
  const m = slice.match(/\((\d{1,3}(?:\.\d{3})*(?:,\d{2})?|\d+(?:,\d{2})?)\s*€\)/);
  if (!m) return null;
  return m[1].replace(/\./g, "").replace(",", ".");
}

type DeedFacts = {
  sellers: DeedPerson[];
  buyers: DeedPerson[];
  representatives: DeedPerson[];
  notary: string | null;
  protocol: number | null;
  address: string | null;
  cadastral: string | null;
  parcela: string | null;
  registry: string | null;
  lawyer: string | null;
  salePrice: string | null;
  referenceValue: string | null;
};

function extractDeedFacts(text: string): DeedFacts {
  const people = deedPeople(text);
  const lower = text.toLowerCase();
  const sellAt = indexOfAny(lower, ["para vender", "parte vendedora"]);
  const buyAt = indexOfAny(lower, ["para comprar", "parte compradora"]);
  const interpAt = indexOfAny(lower, ["intérprete", "interprete"]);
  const intervienen = lower.indexOf("intervienen");
  let exponen = indexOfAny(lower, ["exponen:", "otorgan:"]);
  if (exponen < 0) exponen = lower.length;
  const interpEnd = interpAt < 0
    ? -1
    : (intervienen > interpAt ? intervienen : interpAt + 800);
  const skipInterp = (p: DeedPerson) =>
    interpAt >= 0 && interpEnd >= 0 && p.index >= interpAt && p.index < interpEnd;
  const sellers = uniqueNie(people.filter((p) =>
    !skipInterp(p) &&
    (sellAt < 0 || p.index >= sellAt) &&
    (buyAt < 0 || p.index < buyAt)
  ));
  const reprAt = lower.indexOf("representaci");
  const represented = uniqueNie(people.filter((p) =>
    !skipInterp(p) && reprAt >= 0 && p.index > reprAt && p.index < exponen
  ));
  const afterBuy = people.filter((p) =>
    !skipInterp(p) && buyAt >= 0 && p.index > buyAt && p.index < exponen
  );
  const buyers = represented.length
    ? represented
    : uniqueNie(afterBuy.filter((p) => !sellers.some((s) => s.nie === p.nie)));
  const representatives = uniqueNie(afterBuy.filter((p) =>
    represented.length > 0 && !represented.some((b) => b.nie === p.nie)
  ));
  const urbAt = lower.indexOf("urbana");
  const urb = urbAt < 0 ? text : text.slice(urbAt, urbAt + 2200);
  const urbFlat = urb.replace(/\n/g, " ");
  const hoy = urbFlat.match(/hoy calle\s+([^,\n]+?),\s+n[úu]mero\s+([^\s,]+)/i);
  const mun = urbFlat.match(/t[ée]rmino de\s+([A-ZÁÉÍÓÚÜÑa-záéíóúüñ]+)/i);
  let address: string | null = null;
  if (hoy) {
    address = tidyName(`calle ${hoy[1]}, ${hoy[2]}${mun ? `, ${mun[1]}` : ""}`);
  }
  const parcela = urb.match(/parcela\s+([A-Z0-9][A-Z0-9.\-]{1,12})/i);
  const cat = text.replace(/\n/g, " ").match(
    /referencia\s+catastral[.\s:\-]*([0-9]{7}[A-Z]{2}[0-9]{4}[A-Z][0-9]{4}[A-Z]{2})/i,
  );
  const lugar = text.replace(/\n/g, " ").match(
    /Registro de la Propiedad de\s+([A-ZÁÉÍÓÚÜÑa-záéíóúüñ\s]+?)(?:\s+N[úu]mero|,)/i,
  );
  const finca = text.replace(/\n/g, " ").match(/finca\s+n[úu]mero\s+([\d.]+)/i);
  const lawyer = text.match(
    /[“"«]([^“"»]{6,80}ABOGAD[^“"»]{0,40})[”"»]/i,
  );
  const priceAt = lower.indexOf("precio de esta compraventa");
  const refAt = lower.indexOf("valor de referencia");
  const notary = text.match(
    /Ante m[ií],\s+([A-ZÁÉÍÓÚÜÑ][A-ZÁÉÍÓÚÜÑ\s.]+?),\s+Notario/i,
  );
  return {
    sellers,
    buyers,
    representatives,
    notary: notary ? tidyName(notary[1]) : null,
    protocol: spanishDeedNumber(text),
    address,
    cadastral: cat?.[1]?.toUpperCase() ?? null,
    parcela: parcela?.[1]?.toUpperCase() ?? null,
    registry: [lugar ? tidyName(lugar[1]) : "", finca ? `finca ${finca[1]}` : ""]
      .filter(Boolean).join(", ") || null,
    lawyer: lawyer ? tidyName(lawyer[1]) : null,
    salePrice: priceAt >= 0 ? firstEuro(text, priceAt, 500) : null,
    referenceValue: refAt >= 0 ? firstEuro(text, refAt, 400) : null,
  };
}

function pickDeedClientFromFacts(
  facts: DeedFacts,
  hint: { nombre: string; nie: string },
): DeedPerson | null {
  const pool = [...facts.buyers, ...facts.sellers, ...facts.representatives];
  if (!pool.length) return null;
  const wantNie = hint.nie.trim() ? normalizeNie(hint.nie) : "";
  if (wantNie) {
    const hit = pool.find((p) => p.nie === wantNie);
    if (hit) return hit;
  }
  const tokens = hint.nombre.trim().toLowerCase().split(/\s+/).filter((t) =>
    t.length >= 2
  );
  if (tokens.length) {
    const hit = pool.find((p) => tokens.some((t) => p.name.toLowerCase().includes(t)));
    if (hit) return hit;
  }
  return facts.buyers[0] ?? pool[0];
}

function escrituraLlmFocus(text: string, head = 4500, chunk = 5000): string {
  if (text.length <= head + 2000) return text;
  const lower = text.toLowerCase();
  let out = text.slice(0, Math.min(head, text.length));
  const add = (label: string, marks: string[], size: number) => {
    const at = indexOfAny(lower, marks);
    if (at < 0) return;
    out += `\n\n--- ${label} ---\n` +
      text.slice(at, Math.min(text.length, at + size));
  };
  add("Comprador", ["para comprar", "parte compradora", "en nombre y representaci"], chunk);
  add("Finca", ["exponen:", "urbana", "referencia catastral"], 4000);
  add("Precio", ["precio de esta compraventa", "es precio de", "otorgan:"], 3500);
  add("Abogado", ["abogad", "letrado", "despacho profesional"], 2500);
  add("Registro", ["registro de la propiedad"], 2000);
  return out;
}

const esNum: Record<string, number> = {
  cero: 0, un: 1, uno: 1, una: 1, dos: 2, tres: 3, cuatro: 4, cinco: 5,
  seis: 6, siete: 7, ocho: 8, nueve: 9, diez: 10, once: 11, doce: 12,
  trece: 13, catorce: 14, quince: 15, dieciseis: 16, diecisiete: 17,
  dieciocho: 18, diecinueve: 19, veinte: 20, veintiun: 21, veintiuno: 21,
  veintidos: 22, veintitres: 23, veinticuatro: 24, veinticinco: 25,
  veintiseis: 26, veintisiete: 27, veintiocho: 28, veintinueve: 29,
  treinta: 30, cuarenta: 40, cincuenta: 50, sesenta: 60, setenta: 70,
  ochenta: 80, noventa: 90, cien: 100, ciento: 100, doscientos: 200,
  trescientos: 300, cuatrocientos: 400, quinientos: 500, seiscientos: 600,
  setecientos: 700, ochocientos: 800, novecientos: 900,
};

function foldEs(raw: string): string {
  return raw.toLowerCase()
    .replace(/á/g, "a")
    .replace(/é/g, "e")
    .replace(/í/g, "i")
    .replace(/ó/g, "o")
    .replace(/ú/g, "u")
    .replace(/ü/g, "u")
    .replace(/ñ/g, "n");
}

function parseSpanishInt(raw: string): number | null {
  let total = 0;
  let current = 0;
  for (const w of foldEs(raw).split(/[^a-z]+/)) {
    if (!w || w === "y") continue;
    if (w === "mil") {
      current = (current === 0 ? 1 : current) * 1000;
      total += current;
      current = 0;
      continue;
    }
    const v = esNum[w];
    if (v == null) continue;
    current += v;
  }
  const n = total + current;
  return n === 0 ? null : n;
}

function spanishDeedNumber(text: string): number | null {
  const head = text.slice(0, 900);
  const m = head.match(/N[ÚU]MERO\s+([A-ZÁÉÍÓÚÜÑ\s]+)/i);
  if (!m) return null;
  const n = parseSpanishInt(m[1]);
  if (n == null || n < 1 || n > 99999) return null;
  return n;
}

function alignDeedFields(
  fields: Record<string, string>,
  bodyText: string,
  hint: { nombre: string; nie: string },
): Record<string, string> {
  if (!looksLikeEscrituraText(bodyText)) return fields;
  const facts = extractDeedFacts(bodyText);
  const next = { ...fields };
  if (facts.sellers.length) {
    next["fields.sellers"] = facts.sellers.map(partyLabel).join("; ");
    if (facts.sellers[0].name) next["fields.seller"] = facts.sellers[0].name;
    next["fields.sellerNie"] = facts.sellers[0].nie;
  }
  if (facts.buyers.length) {
    next["fields.buyers"] = facts.buyers.map(partyLabel).join("; ");
  }
  if (facts.representatives.length) {
    next["fields.attorney"] = facts.representatives.map(partyLabel).join("; ");
  }
  if (facts.notary) next["fields.notary"] = facts.notary;
  if (facts.protocol != null) next["fields.protocol"] = `${facts.protocol}`;
  if (facts.address) next["fields.address"] = facts.address;
  if (facts.cadastral) next["fields.cadastral"] = facts.cadastral;
  if (facts.parcela) next["fields.parcela"] = facts.parcela;
  if (facts.registry) next["fields.registry"] = facts.registry;
  if (facts.lawyer) next["fields.lawyer"] = facts.lawyer;
  if (facts.salePrice) next["fields.salePrice"] = facts.salePrice;
  if (facts.referenceValue) next["fields.referenceValue"] = facts.referenceValue;
  const client = pickDeedClientFromFacts(facts, hint);
  if (client) {
    next["fields.nie"] = client.nie;
    next["fields.nombre"] = hint.nombre.trim() || client.name;
  } else if (facts.buyers[0]) {
    next["fields.nie"] = facts.buyers[0].nie;
    if (facts.buyers[0].name) next["fields.nombre"] = facts.buyers[0].name;
  }
  for (const k of [
    "fields.expiry",
    "fields.issued",
    "fields.nationality",
    "fields.docNumber",
    "fields.tel",
  ]) {
    delete next[k];
  }
  return sanitizeFields(next);
}
