import '../ai/extract_queue.dart';
import '../ai/extract_text.dart';
import 'carpeta_controller.dart';
import 'documento_library.dart';
import 'stoh.dart';
import 'stoh_queue.dart';

/// Filtr knihovny. Ne volný tag.
enum LibraryScope { all, pile, placed, duplicates, unknown }

class LibraryPaper {
  const LibraryPaper({
    required this.document,
    this.draftId,
    this.draftFields = const {},
    this.dupKind,
    this.inmuebleLabel = '',
  });

  final CarpetaDocumento document;
  final String? draftId;
  final Map<String, String> draftFields;
  final DocumentoDupKind? dupKind;
  final String inmuebleLabel;

  bool get onPile => document.albumKeys.isEmpty;

  bool get pending => isExtractPending(draftFields);

  bool get failed => isExtractFailed(draftFields);

  LibraryPaper copyWith({String? inmuebleLabel}) {
    return LibraryPaper(
      document: document,
      draftId: draftId,
      draftFields: draftFields,
      dupKind: dupKind,
      inmuebleLabel: inmuebleLabel ?? this.inmuebleLabel,
    );
  }

  StohProposal get proposal => classifyStohPaper(
        originalName: document.originalName,
        bodyText: draftFields['body_text'] ?? document.bodyText ?? '',
        fields: {
          ...document.extracted,
          ...draftFields,
        },
      );

  Map<String, String> get glanceFields {
    final fromDoc = extractProposalFields(document.extracted);
    final fromDraft = extractProposalFields(draftFields);
    return {...fromDoc, ...fromDraft};
  }

  String get groupKey => pileGroupKey(
        proposedBloque: onPile
            ? proposal.bloqueKey
            : (document.albumKeys.isEmpty ? '' : document.albumKeys.first),
        originalName: document.originalName,
        tipo: document.tipo,
      );
}

/// Pole, která má smysl číst bez otevření. Ne dump fields.*.
const kLibraryGlanceKeys = <String>[
  'fields.amount',
  'fields.company',
  'fields.holder',
  'fields.periodFrom',
  'fields.periodTo',
  'fields.invoiceNo',
  'fields.cups',
  'fields.nie',
  'fields.nombre',
  'fields.lawyer',
  'fields.email',
  'fields.expiry',
  'fields.address',
  'fields.attorney',
  'fields.date',
  'fields.issued',
];

List<MapEntry<String, String>> libraryGlanceEntries(
  Map<String, String> fields, {
  int max = 4,
}) {
  final out = <MapEntry<String, String>>[];
  for (final key in kLibraryGlanceKeys) {
    final v = (fields[key] ?? '').trim();
    if (v.isEmpty) continue;
    out.add(MapEntry(key, v));
    if (out.length >= max) break;
  }
  return out;
}

/// Čip finca: adresa, catastral, adresa z papíru. Nikdy UUID.
String libraryFincaLabel(
  LibraryInmueble? inm, {
  Iterable<LibraryPaper> papers = const [],
}) {
  if (inm == null) return '';
  final dir = inm.direccion.trim();
  if (dir.isNotEmpty) return dir;
  final cat = inm.catastral.trim();
  if (cat.isNotEmpty) return cat;
  for (final p in papers) {
    if ((p.document.inmuebleId ?? '') != inm.id) continue;
    final addr = (p.glanceFields['fields.address'] ?? '').trim();
    if (addr.isNotEmpty) return addr;
  }
  return '';
}

int libraryPaperYear(LibraryPaper paper) {
  final f = paper.glanceFields;
  return yearFromPaperDate(
    (f['fields.issued'] ?? '').trim().isNotEmpty
        ? f['fields.issued']!
        : (f['fields.date'] ?? f['fields.periodTo'] ?? f['fields.expiry'] ?? ''),
  );
}

List<LibraryPaper> buildLibraryPapers({
  required List<CarpetaDocumento> documents,
  required List<StohQueueRow> drafts,
  required List<LibraryInmueble> inmuebles,
}) {
  final draftByPath = <String, StohQueueRow>{};
  for (final d in drafts) {
    draftByPath[d.document.storagePath] = d;
  }
  final hints = [
    for (final d in documents)
      LibraryPaperHint(
        id: d.id,
        originalName: d.originalName,
        contentSha256: d.contentSha256,
        invoiceNo: d.extracted['fields.invoiceNo'] ?? '',
        period:
            '${d.extracted['fields.periodFrom'] ?? ''}|${d.extracted['fields.periodTo'] ?? ''}',
        amount: d.extracted['fields.amount'] ?? '',
      ),
  ];
  final inmById = {for (final p in inmuebles) p.id: p};
  final out = <LibraryPaper>[
    for (final doc in documents)
      () {
        final draft = draftByPath[doc.storagePath];
        final amount = (draft?.fields['fields.amount'] ??
                doc.extracted['fields.amount'] ??
                '')
            .trim();
        final invoiceNo = (draft?.fields['fields.invoiceNo'] ??
                doc.extracted['fields.invoiceNo'] ??
                '')
            .trim();
        final period =
            '${draft?.fields['fields.periodFrom'] ?? doc.extracted['fields.periodFrom'] ?? ''}|${draft?.fields['fields.periodTo'] ?? doc.extracted['fields.periodTo'] ?? ''}';
        return LibraryPaper(
          document: doc,
          draftId: draft?.draftId,
          draftFields: draft?.fields ?? const {},
          dupKind: matchDocumentoDuplicate(
            originalName: doc.originalName,
            contentSha256: doc.contentSha256,
            invoiceNo: invoiceNo,
            period: period,
            amount: amount,
            live: hints,
            excludeId: doc.id,
          ),
          inmuebleLabel: libraryFincaLabel(
            inmById[doc.inmuebleId ?? ''],
          ),
        );
      }(),
  ];
  out.sort((a, b) {
    final at = a.document.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bt = b.document.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bt.compareTo(at);
  });
  return [
    for (final p in out)
      p.inmuebleLabel.isNotEmpty
          ? p
          : p.copyWith(
              inmuebleLabel: libraryFincaLabel(
                inmById[p.document.inmuebleId ?? ''],
                papers: out,
              ),
            ),
  ];
}

List<LibraryPaper> filterLibraryPapers({
  required List<LibraryPaper> papers,
  required LibraryScope scope,
  String? inmuebleId,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final p in papers)
      if (_scopeKeeps(p, scope) &&
          _inmuebleKeeps(p, inmuebleId) &&
          _queryKeeps(p, q))
        p,
  ];
}

bool _scopeKeeps(LibraryPaper p, LibraryScope scope) {
  return switch (scope) {
    LibraryScope.all => true,
    LibraryScope.pile => p.onPile,
    LibraryScope.placed => !p.onPile,
    LibraryScope.duplicates => p.dupKind != null,
    LibraryScope.unknown => p.onPile && p.groupKey == PileGroup.unknown.key,
  };
}

bool _inmuebleKeeps(LibraryPaper p, String? inmuebleId) {
  final id = (inmuebleId ?? '').trim();
  if (id.isEmpty) return true;
  return (p.document.inmuebleId ?? '') == id;
}

bool _queryKeeps(LibraryPaper p, String q) {
  if (q.isEmpty) return true;
  final hay = [
    p.document.originalName,
    p.document.bodyText ?? '',
    p.inmuebleLabel,
    ...p.glanceFields.values,
  ].join('\n').toLowerCase();
  return hay.contains(q);
}

/// Hromada po skupinách. Zařazené papíry sem nepatří.
Map<String, List<LibraryPaper>> groupPilePapers(Iterable<LibraryPaper> papers) {
  final grouped = <String, List<LibraryPaper>>{};
  for (final p in papers) {
    if (!p.onPile) continue;
    grouped.putIfAbsent(p.groupKey, () => []).add(p);
  }
  final ordered = <String, List<LibraryPaper>>{};
  for (final key in pileGroupOrder(grouped.keys)) {
    ordered[key] = grouped[key]!;
  }
  return ordered;
}
