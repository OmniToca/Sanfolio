import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/inbox/inbox_providers.dart';

void main() {
  test('snooze schová jen dokud je until po dnešku', () {
    final today = DateTime(2026, 9, 12);
    expect(isPlazoSnoozed(today: today), isFalse);
    expect(
      isPlazoSnoozed(snoozeUntil: DateTime(2026, 9, 12), today: today),
      isFalse,
    );
    expect(
      isPlazoSnoozed(snoozeUntil: DateTime(2026, 9, 13), today: today),
      isTrue,
    );
  });

  test('ruční řádek má snooze, díra dokumentu ne', () {
    const manual = InboxRow(
      clienteId: 'c',
      clienteNombre: 'Ana',
      bloqueKey: 'manual',
      itemKind: 'due_soon',
      plazoId: 'p1',
      plazoSource: 'manual',
      plazoNote: 'Cita notario',
    );
    const hole = InboxRow(
      clienteId: 'c',
      clienteNombre: 'Ana',
      bloqueKey: 'escritura',
      itemKind: 'missing_document',
    );
    expect(manual.canSnooze, isTrue);
    expect(hole.canSnooze, isFalse);
  });
}
