import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/auth/staff_access.dart';

void main() {
  const scoped = StaffAccessScope(
    scoped: true,
    bloqueKeys: ['agua', 'luz'],
    clienteIds: ['a'],
  );

  test('owner a nescopovaný vidí vše', () {
    expect(
      staffMaySeeBloque(
        isOwner: true,
        scope: scoped,
        templateKey: 'escritura',
      ),
      isTrue,
    );
    expect(
      staffMaySeeCliente(
        isOwner: false,
        scope: StaffAccessScope.open,
        clienteId: 'x',
      ),
      isTrue,
    );
  });

  test('scoped vidí identitu a jen vybrané bloky a karty', () {
    expect(
      staffMaySeeBloque(
        isOwner: false,
        scope: scoped,
        templateKey: 'cliente_snapshot',
      ),
      isTrue,
    );
    expect(
      staffMaySeeBloque(isOwner: false, scope: scoped, templateKey: 'luz'),
      isTrue,
    );
    expect(
      staffMaySeeBloque(
        isOwner: false,
        scope: scoped,
        templateKey: 'escritura',
      ),
      isFalse,
    );
    expect(
      staffMaySeeCliente(isOwner: false, scope: scoped, clienteId: 'a'),
      isTrue,
    );
    expect(
      staffMaySeeCliente(isOwner: false, scope: scoped, clienteId: 'b'),
      isFalse,
    );
  });

  test('scoped nezakládá nové karty', () {
    expect(
      staffMayCreateClientes(isOwner: true, scope: scoped),
      isTrue,
    );
    expect(
      staffMayCreateClientes(
        isOwner: false,
        scope: StaffAccessScope.open,
      ),
      isTrue,
    );
    expect(
      staffMayCreateClientes(isOwner: false, scope: scoped),
      isFalse,
    );
  });
}
