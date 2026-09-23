/**
 * Řez přepisu a OpenAI embedding. Index, ne Guardar desky.
 * Stejná pravidla jako Dart `splitDocumentBodyText`.
 */

const PAGE_MARK = /---\s*Strana\s+\d+\s*\/\s*\d+\s*---/g;
const MIN_CHARS = 40;
const WINDOW = 1200;
const OVERLAP = 200;
const MAX_CHUNKS = 80;
const EMBED_MODEL = "text-embedding-3-small";

export function splitDocumentBodyText(body: string): string[] {
  const t = body.trim();
  if (!t) return [];
  const pages = t.split(PAGE_MARK).map((s) => s.trim()).filter((s) =>
    s.length >= MIN_CHARS
  );
  if (pages.length >= 2) return pages.slice(0, MAX_CHUNKS);
  if (t.length <= WINDOW) return t.length >= MIN_CHARS ? [t] : [];
  const out: string[] = [];
  const step = WINDOW - OVERLAP;
  for (let i = 0; i < t.length && out.length < MAX_CHUNKS; i += step) {
    const chunk = t.slice(i, i + WINDOW).trim();
    if (chunk.length >= MIN_CHARS) out.push(chunk);
  }
  return out;
}

export async function embedTexts(
  apiKey: string,
  inputs: string[],
): Promise<number[][]> {
  const out: number[][] = [];
  for (let i = 0; i < inputs.length; i += 20) {
    const batch = inputs.slice(i, i + 20);
    const res = await fetch("https://api.openai.com/v1/embeddings", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ model: EMBED_MODEL, input: batch }),
    });
    if (!res.ok) {
      throw new Error(`embed ${res.status}`);
    }
    const data = await res.json() as {
      data?: Array<{ embedding?: number[]; index?: number }>;
    };
    const rows = [...(data.data ?? [])].sort((a, b) =>
      (a.index ?? 0) - (b.index ?? 0)
    );
    for (const row of rows) {
      if (Array.isArray(row.embedding) && row.embedding.length === 1536) {
        out.push(row.embedding);
      }
    }
  }
  if (out.length !== inputs.length) {
    throw new Error("embed count mismatch");
  }
  return out;
}

export async function replaceDocumentoChunks(args: {
  userClient: {
    rpc: (
      fn: string,
      params: Record<string, unknown>,
    ) => Promise<{ error: { message: string } | null }>;
  };
  documentoId: string;
  body: string;
  apiKey: string;
}): Promise<void> {
  const parts = splitDocumentBodyText(args.body);
  if (parts.length === 0) {
    const { error } = await args.userClient.rpc("replace_documento_chunks", {
      p_documento_id: args.documentoId,
      p_chunks: [],
    });
    if (error) throw new Error(error.message);
    return;
  }
  const vectors = await embedTexts(args.apiKey, parts);
  const chunks = parts.map((content, i) => ({
    chunk_index: i,
    content,
    embedding: vectors[i],
  }));
  const { error } = await args.userClient.rpc("replace_documento_chunks", {
    p_documento_id: args.documentoId,
    p_chunks: chunks,
  });
  if (error) throw new Error(error.message);
}
