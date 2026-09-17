import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/clientes/reach_gaps.dart';

void main() {
  test('sin_canal je karta i kontakt bez e-mailu i telefonu', () {
    final gap = classifyReachGap(
      cardEmail: '',
      cardTel: null,
      cardLocale: 'cs',
    );
    expect(gap.sinCanal, isTrue);
    expect(gap.contactOnly, isFalse);
    expect(gap.canCopy, isFalse);
    expect(gap.hasGap, isTrue);
  });

  test('kontakt stačí na Pedir, locale na kartě se nepřepisuje', () {
    final gap = classifyReachGap(
      cardEmail: null,
      cardTel: '',
      cardLocale: 'en',
      contactEmail: 'ana@example.com',
      contactTel: '+34600000000',
      contactLocale: 'es',
    );
    expect(gap.sinCanal, isFalse);
    expect(gap.contactOnly, isTrue);
    expect(gap.noLocale, isFalse);
    expect(gap.canCopy, isTrue);
  });

  test('locale se kopíruje jen když na kartě není cs/en/es/de/fr', () {
    expect(
      classifyReachGap(cardLocale: 'cs', contactLocale: 'es').canCopy,
      isFalse,
    );
    expect(
      classifyReachGap(cardLocale: 'xx', contactLocale: 'es').canCopy,
      isTrue,
    );
    expect(reachLocaleValid('CS'), isTrue);
    expect(reachLocaleValid(''), isFalse);
  });

  test('doplnění z kontaktu sahá na první díru, ne na vyplněnou kartu', () {
    expect(
      canCopyChannelFromContacts(
        cardEmail: 'a@b.c',
        cardTel: '+1',
        cardLocale: 'cs',
        contacts: [(email: 'x@y.z', tel: '+2', locale: 'es')],
      ),
      isFalse,
    );
    expect(
      canCopyChannelFromContacts(
        cardEmail: null,
        cardTel: null,
        cardLocale: 'cs',
        contacts: [(email: 'x@y.z', tel: null, locale: 'es')],
      ),
      isTrue,
    );
  });

  test('RPC řádek bere díru i když SQL flag chybí', () {
    final row = reachGapRowFromRpc({
      'cliente_id': 'c1',
      'cliente_nombre': 'Ana',
      'email': '',
      'tel': null,
      'locale': 'cs',
      'contact_email': 'ana@example.com',
    });
    expect(row?.gap.contactOnly, isTrue);
    expect(row?.gap.canCopy, isTrue);
    expect(reachGapRowFromRpc({'cliente_nombre': 'Ana'}), isNull);
  });
}
