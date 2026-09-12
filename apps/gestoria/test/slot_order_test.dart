import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/modules/slot_order.dart';

void main() {
  test('prázdné slot_order nechá katalog', () {
    expect(
      applySlotOrder(
        items: ['a', 'b', 'c'],
        order: const [],
        keyOf: (k) => k,
      ),
      ['a', 'b', 'c'],
    );
  });

  test('slot_order přeskládá známé klíče a doplní zbytek', () {
    expect(
      applySlotOrder(
        items: ['cliente_snapshot', 'escritura', 'agua', 'luz'],
        order: const ['agua', 'escritura'],
        keyOf: (k) => k,
      ),
      ['agua', 'escritura', 'cliente_snapshot', 'luz'],
    );
  });

  test('šipka v nastavení vymění sousedy', () {
    expect(moveKey(['a', 'b', 'c'], 1, -1), ['b', 'a', 'c']);
    expect(moveKey(['a', 'b', 'c'], 0, -1), ['a', 'b', 'c']);
  });
}
