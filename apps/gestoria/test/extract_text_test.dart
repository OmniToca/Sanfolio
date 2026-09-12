import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/ai/documento_fields.dart';
import 'package:gestoria_os/features/ai/extract_text.dart';

void main() {
  test('extract najde NIE, e-mail a tel, nic neukládá', () {
    final out = extractFromText(
      'Cliente ANA, NIE Y1234567E, mail ana@test.com, tel +34 612 345 678',
    );
    expect(out.nie, 'Y1234567E');
    expect(out.email, 'ana@test.com');
    expect(out.tel, '+34612345678');
  });

  test('žlutý diff ukáže změnu a prázdné teď, nic neukládá', () {
    final diffs = prefillDiffs(
      current: {'fields.nie': '', 'fields.email': 'old@test.com'},
      proposed: {
        'fields.nie': 'Y1234567E',
        'fields.email': 'old@test.com',
        'fields.tel': '+34612345678',
      },
    );
    expect(diffs.length, 3);
    expect(diffs.first.changed, isTrue);
    expect(diffs[1].changed, isFalse);
    expect(stringFieldMap({'fields.nie': 'Y1234567E', 'skip': ''}), {
      'fields.nie': 'Y1234567E',
    });
  });

  test('odpad z PDF se nenabízí místo platného NIE', () {
    expect(looksLikeNie('XU'), isFalse);
    expect(looksLikeNie('Y9736943E'), isTrue);
    expect(looksLikeTel('0000000000278' * 8), isFalse);
    expect(looksLikeTel('+420775869555'), isTrue);
    expect(
      sanitizeExtractedFields({
        'fields.nie': 'XU',
        'fields.tel': '278000000000333330027833327827856556556556556556',
      }),
      isEmpty,
    );
    final diffs = prefillDiffs(
      current: {'fields.nie': 'Y9736943E', 'fields.tel': '+420775869555'},
      proposed: {'fields.nie': 'XU', 'fields.tel': '0000000000278'},
    );
    expect(diffs, isEmpty);
  });

  test('jméno na pase pozná stejného člověka', () {
    expect(namesLikelyMatch('Petr Sokol', 'SOKOL, PETR'), isTrue);
    expect(namesLikelyMatch('Petr Sokol', 'Ana García'), isFalse);
  });
}
