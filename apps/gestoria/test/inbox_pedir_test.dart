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

  test('hromadný Pedir počítá drafty, sin_canal a čerstvé Pedir', () {
    final last = DateTime.utc(2026, 9, 10, 10);
    final plan = planPedirDrafts(
      [
        const PedirDraftRequest(
          clienteId: 'a',
          clienteNombre: 'Ana',
          templateKey: 'recordatorio',
          bloqueKey: 'modelo_210',
          hasEmail: true,
        ),
        const PedirDraftRequest(
          clienteId: 'b',
          clienteNombre: 'Bea',
          templateKey: 'falta_documento',
          bloqueKey: 'modelo_210',
          hasEmail: false,
          hasTel: false,
        ),
        PedirDraftRequest(
          clienteId: 'c',
          clienteNombre: 'Cira',
          templateKey: 'recordatorio',
          bloqueKey: 'plusvalia',
          hasEmail: true,
          lastRequestedAt: last,
        ),
      ],
      nudgeIntervalDays: 7,
      now: DateTime.utc(2026, 9, 12, 10),
    );
    expect(plan.toDraft.map((r) => r.clienteId), ['a']);
    expect(plan.noChannel, 1);
    expect(plan.askedRecently, 1);
    expect(
      pedirRequestFromInbox(
        const InboxRow(
          clienteId: 'c',
          clienteNombre: 'Ana',
          bloqueKey: 'escritura',
          itemKind: 'missing_document',
        ),
      ).templateKey,
      'falta_documento',
    );
  });
}
