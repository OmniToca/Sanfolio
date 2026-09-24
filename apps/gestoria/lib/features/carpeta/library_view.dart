import '../../core/time/office_date.dart';
import '../ai/documento_fields.dart';
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
    return overlayIbanFromBody(
      {...fromDoc, ...fromDraft},
      bodyText: draftFields['body_text'] ?? document.bodyText ?? '',
    );
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
  'fields.iban',
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

/// Glance čipy na kartě stohu: NIE, jméno, IBAN mask, adresa, datum.
const kLibraryCardGlanceKeys = <String>[
  'fields.nie',
  'fields.nombre',
  'fields.iban',
  'fields.address',
  'fields.date',
  'fields.issued',
];

List<MapEntry<String, String>> libraryGlanceEntries(
  Map<String, String> fields, {
  int max = 4,
  List<String> keys = kLibraryGlanceKeys,
}) {
  final out = <MapEntry<String, String>>[];
  for (final key in keys) {
    final v = (fields[key] ?? '').trim();
    if (v.isEmpty) continue;
    final shown = key == 'fields.iban'
        ? maskIban(v)
        : (key == 'fields.date' ||
                key == 'fields.issued' ||
                key == 'fields.expiry')
            ? (toDmyDate(v) ?? v)
            : v;
    out.add(MapEntry(key, shown));
    if (out.length >= max) break;
  }
  return out;
}

/// dni_nie vs. factura — ne razítko KLIENT. Other bere návrh z názvu.
String libraryPaperTipo(LibraryPaper row) {
  final t = row.document.tipo.trim();
  if (t.isNotEmpty && t != 'other') return t;
  final p = row.proposal.tipo.trim();
  return p.isEmpty ? 'other' : p;
}

/// Prose summary: DB sloupec, draft field, nebo strukturovaný auto-summary.
String libraryPaperProseSummary(
  LibraryPaper row, {
  required String Function(String key, {Map<String, String> named}) tr,
}) {
  final fromDoc = row.document.aiSummary.trim();
  if (fromDoc.isNotEmpty) return fromDoc;
  final fromDraft = (row.draftFields['ai_summary'] ?? '').trim();
  if (fromDraft.isNotEmpty) return fromDraft;
  return libraryPaperAutoSummary(row, tr: tr);
}

/// Levný náhled: jen obrázek ze storage. PDF bez pre-renderu → null.
bool libraryPaperHasImageThumb(String storagePath, String originalName) {
  final hay = '${storagePath.toLowerCase()}\n${originalName.toLowerCase()}';
  return RegExp(r'\.(jpe?g|png|webp|gif)(\?|$)').hasMatch(hay);
}

String? _glanceVal(Map<String, String> f, String key) {
  final v = (f[key] ?? '').trim();
  return v.isEmpty ? null : v;
}

String? _glanceDate(Map<String, String> f, String key) {
  final raw = _glanceVal(f, key);
  if (raw == null) return null;
  return toDmyDate(raw) ?? raw;
}

void _addSummaryBit(List<String> bits, String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty || bits.contains(v)) return;
  bits.add(v);
}

/// Věta bez „NIE: … · Jméno: …“. Datum narození u DNI není rok papíru.
String libraryPaperAutoSummary(
  LibraryPaper row, {
  required String Function(String key, {Map<String, String> named}) tr,
}) {
  final tipo = libraryPaperTipo(row);
  final f = row.glanceFields;
  final bits = <String>[];
  _addSummaryBit(bits, stohDocumentTitle(
        row.draftFields['body_text'] ?? row.document.bodyText ?? '',
      ));
  if (tipo == 'dni_nie' || tipo == 'pasaporte') {
    _addSummaryBit(bits, _glanceVal(f, 'fields.nie') ?? _glanceVal(f, 'fields.docNumber'));
    _addSummaryBit(bits, _glanceVal(f, 'fields.nombre'));
    final born = _glanceDate(f, 'fields.date');
    if (born != null) {
      _addSummaryBit(bits, tr('stoh.born', named: {'date': born}));
    }
    _addSummaryBit(bits, _glanceVal(f, 'fields.lawyer'));
  } else if (tipo == 'copia_escritura') {
    _addSummaryBit(bits, _glanceVal(f, 'fields.address'));
    _addSummaryBit(bits, _glanceDate(f, 'fields.date') ?? _glanceDate(f, 'fields.issued'));
    _addSummaryBit(bits, _glanceVal(f, 'fields.notary'));
    _addSummaryBit(bits, _glanceVal(f, 'fields.lawyer'));
    _addSummaryBit(bits, _glanceVal(f, 'fields.buyers'));
    _addSummaryBit(bits, _glanceVal(f, 'fields.sellers'));
  } else if (isInvoiceDocTipo(tipo)) {
    _addSummaryBit(bits, _glanceVal(f, 'fields.company'));
    _addSummaryBit(bits, _glanceVal(f, 'fields.amount'));
    final from = _glanceDate(f, 'fields.periodFrom');
    final to = _glanceDate(f, 'fields.periodTo');
    if (from != null && to != null) {
      _addSummaryBit(bits, '$from – $to');
    } else {
      _addSummaryBit(bits, from ?? to ?? _glanceDate(f, 'fields.issued'));
    }
    _addSummaryBit(bits, _glanceVal(f, 'fields.invoiceNo'));
  } else if (tipo == 'copia_poder') {
    _addSummaryBit(
      bits,
      _glanceVal(f, 'fields.attorney') ?? _glanceVal(f, 'fields.lawyer'),
    );
    final exp = _glanceDate(f, 'fields.expiry');
    if (exp != null) {
      _addSummaryBit(bits, tr('stoh.until', named: {'date': exp}));
    }
  } else if (tipo == 'justificante_iban') {
    final iban = _glanceVal(f, 'fields.iban');
    if (iban != null) _addSummaryBit(bits, formatIban(iban));
    _addSummaryBit(
      bits,
      _glanceVal(f, 'fields.holder') ?? _glanceVal(f, 'fields.company'),
    );
  } else {
    for (final e in libraryGlanceEntries(f, max: 5)) {
      if (e.key == 'fields.date' ||
          e.key == 'fields.issued' ||
          e.key == 'fields.expiry' ||
          e.key == 'fields.periodFrom' ||
          e.key == 'fields.periodTo') {
        _addSummaryBit(bits, toDmyDate(e.value) ?? e.value);
      } else {
        _addSummaryBit(bits, e.value);
      }
    }
  }
  return bits.join(' · ');
}

bool libraryShowsYearChip(LibraryPaper row) {
  final tipo = libraryPaperTipo(row);
  if (tipo == 'dni_nie' || tipo == 'pasaporte' || tipo == 'copia_poder') {
    return false;
  }
  if (row.proposal.bloqueKey == 'cliente_snapshot') return false;
  return libraryPaperYear(row) > 0;
}

/// Guardar zapsal pole. Prázdné extracted = jen šanon, deska ještě ne.
bool libraryPaperOnDesk(LibraryPaper row) {
  return extractProposalFields(row.document.extracted).isNotEmpty;
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
    p.document.caption,
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
