import 'package:crypto/crypto.dart';

import 'stoh.dart';

/// Návrh alba, který AI smí zapsat. Konflikt dvou hádání = hromada.
const kFincaBloqueKeys = <String>{
  'escritura',
  'agua',
  'luz',
  'gaz',
  'comunidad',
  'suma',
  'plusvalia',
  'seguro',
  'alarma',
};

/// DNI / pas / NIE / poder žijí u člověka, ne u bytu.
const kPersonBloqueKeys = <String>{
  'cliente_snapshot',
  'nie_tramite',
  'poder',
};

enum DocumentoDupKind { bytes, name, invoice }

class LibraryInmueble {
  const LibraryInmueble({
    required this.id,
    this.direccion = '',
    this.catastral = '',
  });

  final String id;
  final String direccion;
  final String catastral;
}

class LibraryPaperHint {
  const LibraryPaperHint({
    required this.id,
    required this.originalName,
    this.contentSha256 = '',
    this.invoiceNo = '',
    this.period = '',
    this.amount = '',
  });

  final String id;
  final String originalName;
  final String contentSha256;
  final String invoiceNo;
  final String period;
  final String amount;
}

/// Skupina hromady. Ne volný tag — jen classify.
class PileGroup {
  const PileGroup(this.key);

  final String key;

  static const unknown = PileGroup('unknown');
  static const mail = PileGroup('mail');
}

bool isFincaBloqueKey(String key) => kFincaBloqueKeys.contains(key);

bool isPersonBloqueKey(String key) => kPersonBloqueKeys.contains(key);

/// Jedna finca na papír: album cizího bytu nejde.
bool placementFitsInmueble({
  required String? paperInmuebleId,
  required String? bloqueInmuebleId,
}) {
  final paper = (paperInmuebleId ?? '').trim();
  final bloque = (bloqueInmuebleId ?? '').trim();
  if (paper.isEmpty || bloque.isEmpty) return true;
  return paper == bloque;
}

/// Změna bytu sundá alba, která visí na jiném inmueble.
List<String> placementsToDropOnInmuebleChange({
  required String? newInmuebleId,
  required Map<String, String?> placementBloqueInmueble,
}) {
  final next = (newInmuebleId ?? '').trim();
  if (next.isEmpty) return const [];
  return [
    for (final e in placementBloqueInmueble.entries)
      if ((e.value ?? '').trim().isNotEmpty && e.value!.trim() != next) e.key,
  ];
}

String normalizeDocumentoFileName(String originalName) {
  var n = originalName.trim().toLowerCase();
  n = n.replaceAll(RegExp(r'[\s_]+'), '_');
  return n;
}

String? invoiceIdentityKey({
  required String invoiceNo,
  required String period,
  required String amount,
}) {
  final no = invoiceNo.trim().toLowerCase();
  final per = period.trim().toLowerCase();
  final amt = amount.trim();
  if (no.isEmpty && amt.isEmpty) return null;
  if (no.isEmpty && per.isEmpty) return null;
  return '$no|$per|$amt';
}

/// Bajty > faktura > název. Koš sem nepatří (volající filtruje živé).
DocumentoDupKind? matchDocumentoDuplicate({
  required String originalName,
  required List<LibraryPaperHint> live,
  String contentSha256 = '',
  String invoiceNo = '',
  String period = '',
  String amount = '',
  String? excludeId,
}) {
  final sha = contentSha256.trim().toLowerCase();
  if (sha.isNotEmpty) {
    for (final p in live) {
      if (excludeId != null && p.id == excludeId) continue;
      if (p.contentSha256.trim().toLowerCase() == sha) {
        return DocumentoDupKind.bytes;
      }
    }
  }
  final identity = invoiceIdentityKey(
    invoiceNo: invoiceNo,
    period: period,
    amount: amount,
  );
  if (identity != null) {
    for (final p in live) {
      if (excludeId != null && p.id == excludeId) continue;
      final other = invoiceIdentityKey(
        invoiceNo: p.invoiceNo,
        period: p.period,
        amount: p.amount,
      );
      if (other == identity) return DocumentoDupKind.invoice;
    }
  }
  final name = normalizeDocumentoFileName(originalName);
  if (name.isEmpty) return null;
  for (final p in live) {
    if (excludeId != null && p.id == excludeId) continue;
    if (normalizeDocumentoFileName(p.originalName) == name) {
      return DocumentoDupKind.name;
    }
  }
  return null;
}

/// Jistý classify: známý blok, žádný konflikt. Jinak hromada.
bool isConfidentStohProposal(StohProposal proposal) {
  return proposal.known &&
      (kFincaBloqueKeys.contains(proposal.bloqueKey) ||
          kPersonBloqueKeys.contains(proposal.bloqueKey));
}

/// Finca z OCR, nebo jediný byt u finca-papíru. DNI nikdy.
String? guessDocumentoInmueble({
  required String proposedBloque,
  required List<LibraryInmueble> properties,
  String address = '',
  String catastral = '',
}) {
  if (isPersonBloqueKey(proposedBloque) || !isFincaBloqueKey(proposedBloque)) {
    return null;
  }
  if (properties.isEmpty) return null;
  final addr = address.trim().toLowerCase();
  final cat = catastral.trim().toLowerCase().replaceAll(' ', '');
  final hits = <LibraryInmueble>[];
  for (final p in properties) {
    final d = p.direccion.trim().toLowerCase();
    final c = p.catastral.trim().toLowerCase().replaceAll(' ', '');
    final byCat = cat.isNotEmpty && c.isNotEmpty && (c == cat || cat.contains(c) || c.contains(cat));
    final byAddr = addr.isNotEmpty && d.isNotEmpty && (addr.contains(d) || d.contains(addr));
    if (byCat || byAddr) hits.add(p);
  }
  if (hits.length == 1) return hits.single.id;
  if (properties.length == 1) return properties.single.id;
  return null;
}

/// Skupina hromady z návrhu, ne z volného tagu.
String pileGroupKey({
  required String proposedBloque,
  String originalName = '',
  String tipo = '',
}) {
  final b = proposedBloque.trim();
  if (kStohBloqueKeys.contains(b)) return b;
  final hay = '${originalName.toLowerCase()}\n${tipo.toLowerCase()}';
  if (RegExp(r'correo|e-?mail|gmail|outlook|whatsapp').hasMatch(hay)) {
    return PileGroup.mail.key;
  }
  return PileGroup.unknown.key;
}

/// Pořadí skupin na hromadě: známé bloky, mail, neznámé.
List<String> pileGroupOrder(Iterable<String> keys) {
  final seen = keys.toSet();
  return [
    for (final k in kStohBloqueOrder)
      if (seen.contains(k)) k,
    if (seen.contains(PileGroup.mail.key)) PileGroup.mail.key,
    if (seen.contains(PileGroup.unknown.key)) PileGroup.unknown.key,
    for (final k in seen)
      if (!kStohBloqueKeys.contains(k) &&
          k != PileGroup.mail.key &&
          k != PileGroup.unknown.key)
        k,
  ];
}

int yearFromPaperDate(String raw) {
  final t = raw.trim();
  final m = RegExp(r'(20\d{2}|19\d{2})').firstMatch(t);
  if (m == null) return 0;
  return int.tryParse(m.group(1)!) ?? 0;
}

/// SHA-256 hex. Stejné bajty u klienta = duplicita.
String documentoContentSha256(List<int> bytes) => sha256.convert(bytes).toString();

/// Spojení fotek, ne řezání PDF.
const kLibraryMergeMax = 20;

bool isLibraryMergeImageName(String originalName, [String storagePath = '']) {
  bool ok(String s) {
    final n = s.trim().toLowerCase();
    return n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png');
  }

  return ok(originalName) || ok(storagePath);
}

/// i18n klíč, nebo null když výběr lze spojit.
String? libraryMergeBlockReason({
  required int count,
  required bool allImages,
}) {
  if (count < 2) return 'stoh.mergeMin';
  if (count > kLibraryMergeMax) return 'stoh.mergeTooMany';
  if (!allImages) return 'stoh.mergeNeedPhotos';
  return null;
}
