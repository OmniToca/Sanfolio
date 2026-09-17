import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/ai/extract_queue.dart';

void main() {
  test('fronta ukáže jen čekající extract, ne uložený ani expirovaný', () {
    expect(
      isWaitingExtract(purpose: 'extract_document', discarded: false),
      isTrue,
    );
    expect(
      isWaitingExtract(purpose: 'extract_text', discarded: false),
      isFalse,
    );
    expect(
      isWaitingExtract(purpose: 'extract_document', discarded: true),
      isFalse,
    );
    expect(
      isWaitingExtract(
        purpose: 'extract_document',
        discarded: false,
        extractedOnDocument: const {'fields.amount': '188.85'},
      ),
      isFalse,
    );
    expect(
      isWaitingExtract(
        purpose: 'extract_document',
        discarded: false,
        expiresAt: DateTime.utc(2026, 9, 16),
        now: DateTime.utc(2026, 9, 17),
      ),
      isFalse,
    );
    expect(
      isWaitingExtract(
        purpose: 'extract_document',
        discarded: false,
        expiresAt: null,
        now: DateTime.utc(2026, 9, 17),
      ),
      isTrue,
    );
  });

  test('Guardar smaže řádek; extracted na dokladu frontu skryje', () {
    final waiting = ExtractQueueRow(
      draftId: 'd1',
      clienteId: 'c1',
      clienteNombre: 'Ana',
      bloqueKey: 'luz',
      documentoId: 'doc1',
      fields: {'fields.amount': '188.85', 'fields.consumption': '1120 kWh'},
      createdAt: DateTime.utc(2026, 9, 16),
    );
    expect(waiting.canGuardar, isTrue);
    final after = extractQueueAfterAction([waiting], 'd1');
    expect(after, isEmpty);
    expect(
      isWaitingExtract(
        purpose: 'extract_document',
        discarded: false,
        extractedOnDocument: const {'fields.amount': '188.85'},
      ),
      isFalse,
    );
  });

  test('pending extract nejde uložit, Zahodit ano', () {
    final pending = ExtractQueueRow(
      draftId: 'd2',
      clienteId: 'c1',
      clienteNombre: 'Ana',
      bloqueKey: 'luz',
      documentoId: 'doc1',
      fields: {'extract_status': 'pending'},
      createdAt: DateTime.utc(2026, 9, 16),
    );
    expect(pending.canGuardar, isFalse);
    expect(pending.pending, isTrue);
    expect(extractProposalFields(pending.fields), isEmpty);
  });
}
