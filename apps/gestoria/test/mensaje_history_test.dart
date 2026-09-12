import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/mensajes/mensaje_providers.dart';

void main() {
  test('historie bere draft a sent, discarded je schovaný', () {
    expect(mensajeInHistory('draft'), isTrue);
    expect(mensajeInHistory('sent'), isTrue);
    expect(mensajeInHistory('discarded'), isFalse);
  });

  test('překlad se ukáže jen když se liší od originálu', () {
    const same = ClienteMensaje(
      id: '1',
      status: 'sent',
      cuerpo: 'Hola',
      localeOriginal: 'es',
      translations: {'cs': 'Hola'},
    );
    const other = ClienteMensaje(
      id: '2',
      status: 'sent',
      cuerpo: 'Hola',
      localeOriginal: 'es',
      translations: {'cs': 'Ahoj'},
    );
    expect(same.translationBesideOriginal('cs'), isNull);
    expect(same.translationBesideOriginal('es'), isNull);
    expect(other.translationBesideOriginal('cs'), 'Ahoj');
  });
}
