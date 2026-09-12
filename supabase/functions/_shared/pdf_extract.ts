/**
 * Text z PDF — unpdf (textová vrstva). Vision je v extract-document.
 * PROČ: contrato / escritura má stránky; fotka občanky jde do vision.
 */

import { extractText, getDocumentProxy } from "npm:unpdf@0.12.1";

const MIN_USABLE = 120;

export async function extractPdfPages(
  pdfBytes: Uint8Array,
): Promise<{ text: string; pages: number }> {
  const pdf = await getDocumentProxy(pdfBytes);
  const { text, totalPages } = await extractText(pdf, { mergePages: false });
  const pages = Array.isArray(text) ? text : [text ?? ""];
  const marked = pages
    .map((pageText, i) => {
      const trimmed = (pageText ?? "").trim();
      return trimmed.length > 0
        ? `--- Strana ${i + 1}/${totalPages} ---\n${trimmed}`
        : "";
    })
    .filter((p) => p.length > 0)
    .join("\n\n");
  return { text: marked.trim(), pages: totalPages ?? pages.length };
}

export function pdfTextUsable(text: string): boolean {
  return text.trim().length >= MIN_USABLE;
}
