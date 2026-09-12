import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/expedientes/expediente_estado.dart';
import 'package:gestoria_os/features/inbox/inbox_providers.dart';

void main() {
  test('stale je jen en_curso po N dnech, 0 vypne', () {
    final today = DateTime(2026, 9, 12);
    final old = DateTime(2026, 8, 1);
    expect(
      isExpedienteStale(
        estado: 'en_curso',
        updatedAt: old,
        staleDays: 14,
        today: today,
      ),
      isTrue,
    );
    expect(
      isExpedienteStale(
        estado: 'abierto',
        updatedAt: old,
        staleDays: 14,
        today: today,
      ),
      isFalse,
    );
    expect(
      isExpedienteStale(
        estado: 'en_curso',
        updatedAt: old,
        staleDays: 0,
        today: today,
      ),
      isFalse,
    );
    expect(
      isExpedienteStale(
        estado: 'en_curso',
        updatedAt: today,
        staleDays: 14,
        today: today,
      ),
      isFalse,
    );
  });

  test('filtr inboxu umí stale_expediente', () {
    const row = InboxRow(
      clienteId: 'c',
      clienteNombre: 'Ana',
      bloqueKey: 'stale_expediente',
      itemKind: 'stale_expediente',
    );
    expect(matchesInboxFilter(row, 'stale_expediente'), isTrue);
    expect(matchesInboxFilter(row, 'due_today'), isFalse);
  });
}
