import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/identity/person_name.dart';

void main() {
  test('složené jméno rozdělí první slovo a zbytek', () {
    expect(splitPersonName(nombre: 'Renata Sušičová'), (
      nombre: 'Renata',
      apellidos: 'Sušičová',
    ));
    expect(splitPersonName(nombre: 'Petr Sokol'), (
      nombre: 'Petr',
      apellidos: 'Sokol',
    ));
    expect(splitPersonName(nombre: 'Juan Carlos', apellidos: 'Pérez López'), (
      nombre: 'Juan Carlos',
      apellidos: 'Pérez López',
    ));
    expect(splitPersonName(nombre: 'Renata'), (
      nombre: 'Renata',
      apellidos: '',
    ));
    expect(joinPersonName('Renata', 'Sušičová'), 'Renata Sušičová');
  });
}
