import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/carpeta/documento_chunks.dart';

void main() {
  test('stránky z přepisu jsou kousky, krátké se zahodí', () {
    final body = [
      '--- Strana 1/2 ---',
      'A' * 50,
      '',
      '--- Strana 2/2 ---',
      'B' * 50,
    ].join('\n');
    final parts = splitDocumentBodyText(body);
    expect(parts.length, 2);
    expect(parts.first.contains('A'), isTrue);
    expect(parts.last.contains('B'), isTrue);
  });

  test('bez značek stran řeže okno s překryvem', () {
    final body = 'x' * 2000;
    final parts = splitDocumentBodyText(body);
    expect(parts.length, 2);
    expect(parts.first.length, 1200);
  });

  test('prázdný a krátký text kousek není', () {
    expect(splitDocumentBodyText(''), isEmpty);
    expect(splitDocumentBodyText('kratky'), isEmpty);
  });
}
