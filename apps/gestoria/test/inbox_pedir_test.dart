import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/inbox/inbox_providers.dart';

void main() {
  test('Pedir je volné, když ještě nikdo nepožádal', () {
    expect(
      canPedirAlCliente(lastRequestedAt: null, nudgeIntervalDays: 7),
      isTrue,
    );
  });

  test('Pedir čeká nudge_interval_days z nastavení kanceláře', () {
    final last = DateTime.utc(2026, 9, 4, 10);
    expect(
      canPedirAlCliente(
        lastRequestedAt: last,
        nudgeIntervalDays: 7,
        now: DateTime.utc(2026, 9, 10, 10),
      ),
      isFalse,
    );
    expect(
      canPedirAlCliente(
        lastRequestedAt: last,
        nudgeIntervalDays: 7,
        now: DateTime.utc(2026, 9, 11, 10),
      ),
      isTrue,
    );
  });

  test('filtr Hoy bere jen due_today, sin_canal bere díru kanálu', () {
    const hole = InboxRow(
      clienteId: 'c',
      clienteNombre: 'Ana',
      bloqueKey: 'escritura',
      itemKind: 'missing_document',
      hasEmail: false,
      hasTel: false,
    );
    const today = InboxRow(
      clienteId: 'c',
      clienteNombre: 'Ana',
      bloqueKey: 'plusvalia',
      itemKind: 'due_today',
    );
    expect(matchesInboxFilter(today, 'due_today'), isTrue);
    expect(matchesInboxFilter(hole, 'due_today'), isFalse);
    expect(matchesInboxFilter(hole, 'missing_document'), isTrue);
    expect(matchesInboxFilter(hole, 'no_channel'), isTrue);
    expect(matchesInboxFilter(today, 'no_channel'), isFalse);
    expect(inboxFilterKeys, contains('due_soon'));
    expect(
      matchesInboxFilter(
        const InboxRow(
          clienteId: 'c',
          clienteNombre: 'Ana',
          bloqueKey: 'plusvalia',
          itemKind: 'due_soon',
        ),
        'due_soon',
      ),
      isTrue,
    );
  });
}
