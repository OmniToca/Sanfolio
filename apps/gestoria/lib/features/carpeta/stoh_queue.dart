import '../ai/ai_providers.dart';
import '../ai/extract_text.dart';
import 'carpeta_controller.dart';
import 'stoh.dart';

/// Řádek skladu: soubor + návrh extract. Guardar je až klik.
class StohQueueRow {
  const StohQueueRow({
    required this.document,
    this.draftId,
    this.fields = const {},
  });

  final CarpetaDocumento document;
  final String? draftId;
  final Map<String, String> fields;

  bool get pending => isExtractPending(fields);
  bool get failed => isExtractFailed(fields);

  StohProposal get proposal => classifyStohPaper(
        originalName: document.originalName,
        bodyText: fields['body_text'] ?? document.bodyText ?? '',
        fields: fields,
      );
}

List<StohQueueRow> mergeStohQueue({
  required List<CarpetaDocumento> documents,
  required List<AiPrefillDraft> drafts,
}) {
  AiPrefillDraft? draftFor(CarpetaDocumento doc) {
    for (final d in drafts) {
      if (d.storagePath == doc.storagePath) return d;
    }
    return null;
  }

  return [
    for (final doc in documents)
      () {
        final draft = draftFor(doc);
        return StohQueueRow(
          document: doc,
          draftId: draft?.draftId,
          fields: draft?.fields ?? const {},
        );
      }(),
  ];
}
