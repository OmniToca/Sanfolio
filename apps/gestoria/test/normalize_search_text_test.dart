import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/search/normalize_search_text.dart';

void main() {
  test('fold jména nesmí smazat mezery (to dělá normalize_id u NIE)', () {
    expect(normalizeSearchText('Monika Sokolová'), 'monika sokolova');
    expect(normalizeSearchText('MONIKA SOKOLOVA'), 'monika sokolova');
    expect(normalizeSearchText('García'), 'garcia');
  });

  test('token AND najde monika sokolova v celém jménu', () {
    expect(
      searchNameMatches('MONIKA SOKOLOVA', 'monika sokolova'),
      isTrue,
    );
    expect(
      searchNameMatches('MONIKA SOKOLOVA', 'Sokolová'),
      isTrue,
    );
    expect(searchNameMatches('Petr Sokol', 'monika sokolova'), isFalse);
  });

  test('jméno+příjmení po splitu (0074) se najde jako celek', () {
    expect(
      searchNameMatches('Renata Sušičová', 'Renata Sušičová'),
      isTrue,
    );
    expect(searchNameMatches('Renata Sušičová', 'Sušičová'), isTrue);
    expect(searchNameMatches('Renata Sušičová', 'renata'), isTrue);
  });
}
