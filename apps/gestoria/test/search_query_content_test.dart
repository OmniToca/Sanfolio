import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/search/search_query_content.dart';

void main() {
  test('stopslova vyhodí, zbude Renata', () {
    expect(searchQueryContent('máme klienta Renata'), 'Renata');
    expect(
      searchQueryContent('jak se jmenují naši klienti'),
      isEmpty,
    );
  });

  test('NIE token z věty', () {
    expect(
      searchQueryIdTokens('jak se jmenuje klient s NIE Y9908856X'),
      contains('Y9908856X'),
    );
    expect(searchQueryIdTokens('Máme klienta Y990 dál'), contains('Y990'));
  });

  test('searchClientQueries sestaví NIE i jméno', () {
    final q = searchClientQueries('máme klienta Renata Sušičová');
    expect(q, contains('Renata Sušičová'));
    final nie = searchClientQueries('klient s NIE Y9908856X');
    expect(nie, contains('Y9908856X'));
  });

  test('list query bez jména', () {
    expect(looksLikeListClientsQuery('jak se jmenují naši klienti'), isTrue);
    expect(looksLikeListClientsQuery('máme klienta Renata'), isFalse);
    expect(looksLikeListClientsQuery('Y9908856X'), isFalse);
  });
}
