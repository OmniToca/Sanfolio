import 'extract_text.dart';

/// Řádek fronty přepisů. Guardar je až klik člověka.
class ExtractQueueRow {
  const ExtractQueueRow({
    required this.draftId,
    required this.clienteId,
    required this.clienteNombre,
    required this.bloqueKey,
    required this.fields,
    required this.createdAt,
    this.storagePath,
    this.documentoId,
    this.docTipo,
    this.originalName,
    this.expedienteId,
  });

  final String draftId;
  final String clienteId;
  final String clienteNombre;
  final String bloqueKey;
  final Map<String, String> fields;
  final DateTime createdAt;
  final String? storagePath;
  final String? documentoId;
  final String? docTipo;
  final String? originalName;
  final String? expedienteId;

  bool get pending => isExtractPending(fields);
  bool get failed => isExtractFailed(fields);

  /// Bez souboru na desce Guardar nemá kam zapsat `extracted`.
  bool get canGuardar =>
      !pending &&
      !failed &&
      documentoId != null &&
      documentoId!.isNotEmpty &&
      extractProposalFields(fields).isNotEmpty;
}

/// Žlutá pole k uložení. Stav LLM a OCR dump sem nepatří.
Map<String, String> extractProposalFields(Map<String, String> fields) {
  return {
    for (final e in fields.entries)
      if (e.key != kExtractStatus &&
          e.key != 'body_text' &&
          e.key != kProposedBloqueKey &&
          e.key != kProposedTipo &&
          e.key != 'ai_summary' &&
          e.key != 'ai_summary_locale' &&
          e.value.trim().isNotEmpty)
        e.key: e.value.trim(),
  };
}

/// Fronta bere jen extract u dokladu, který gestor ještě neuložil.
bool isWaitingExtract({
  required String purpose,
  required bool discarded,
  DateTime? expiresAt,
  Map<String, String> extractedOnDocument = const {},
  DateTime? now,
}) {
  if (discarded) return false;
  if (purpose != 'extract_document') return false;
  final t = now ?? DateTime.now().toUtc();
  if (expiresAt != null && !expiresAt.isAfter(t)) return false;
  if (extractedOnDocument.isNotEmpty) return false;
  return true;
}

/// Guardar smaže řádek z fronty. Zahodit taky — extracted se nezapisuje.
List<ExtractQueueRow> extractQueueAfterAction(
  List<ExtractQueueRow> rows,
  String draftId,
) {
  return [for (final r in rows) if (r.draftId != draftId) r];
}

ExtractQueueRow? extractQueueRowFromRpc(Map raw) {
  final draftId = '${raw['draft_id'] ?? ''}'.trim();
  final clienteId = '${raw['cliente_id'] ?? ''}'.trim();
  if (draftId.isEmpty || clienteId.isEmpty) return null;
  final created = DateTime.tryParse('${raw['created_at'] ?? ''}');
  return ExtractQueueRow(
    draftId: draftId,
    clienteId: clienteId,
    clienteNombre: '${raw['cliente_nombre'] ?? ''}'.trim(),
    bloqueKey: '${raw['bloque_key'] ?? 'cliente_snapshot'}'.trim(),
    storagePath: _opt(raw['storage_path']),
    documentoId: _opt(raw['documento_id']),
    docTipo: _opt(raw['doc_tipo']),
    originalName: _opt(raw['original_name']),
    expedienteId: _opt(raw['expediente_id']),
    fields: stringFieldMap(raw['fields']),
    createdAt: created?.toUtc() ?? DateTime.now().toUtc(),
  );
}

String? _opt(Object? raw) {
  final v = '${raw ?? ''}'.trim();
  return v.isEmpty || v == 'null' ? null : v;
}
