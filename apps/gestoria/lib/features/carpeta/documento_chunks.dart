/// Řez `body_text` na kousky. Stejná pravidla jako Edge `embed_chunks.ts`.
const kChunkMinChars = 40;
const kChunkWindow = 1200;
const kChunkOverlap = 200;
const kChunkMax = 80;

final _pageMark = RegExp(r'---\s*Strana\s+\d+\s*/\s*\d+\s*---');

List<String> splitDocumentBodyText(String body) {
  final t = body.trim();
  if (t.isEmpty) return const [];
  final pages = [
    for (final p in t.split(_pageMark))
      if (p.trim().length >= kChunkMinChars) p.trim(),
  ];
  if (pages.length >= 2) {
    return pages.length > kChunkMax ? pages.sublist(0, kChunkMax) : pages;
  }
  if (t.length <= kChunkWindow) {
    return t.length >= kChunkMinChars ? [t] : const [];
  }
  final out = <String>[];
  final step = kChunkWindow - kChunkOverlap;
  for (var i = 0; i < t.length && out.length < kChunkMax; i += step) {
    final end = i + kChunkWindow > t.length ? t.length : i + kChunkWindow;
    final chunk = t.substring(i, end).trim();
    if (chunk.length >= kChunkMinChars) out.add(chunk);
  }
  return out;
}
