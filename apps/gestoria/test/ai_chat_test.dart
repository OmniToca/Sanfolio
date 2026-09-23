import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/ai/ai_chat.dart';
import 'package:gestoria_os/features/ai/ai_providers.dart';

void main() {
  test('panel je na širokém stole otevřený, dokud ho gestor neskryje', () {
    expect(aiPanelVisible(width: 1280, preference: null), isTrue);
    expect(aiPanelVisible(width: 800, preference: null), isFalse);
    expect(aiPanelVisible(width: 800, preference: true), isTrue);
    expect(aiPanelDocked(1280), isTrue);
    expect(aiPanelDocked(800), isFalse);
  });

  test('payload schová odkazy na složku, text zůstane čitelný', () {
    final encoded = encodeAiChatPayload(
      const AiChatPayload(
        text: 'Uložené doklady — Petr',
        opens: [
          AiChatOpen(
            clienteId: '11111111-1111-1111-1111-111111111111',
            label: 'Petr Sokol',
            carpeta: true,
          ),
        ],
        fields: {'fields.nie': 'Y9736943E'},
      ),
    );
    final decoded = decodeAiChatPayload(encoded);
    expect(decoded.text, 'Uložené doklady — Petr');
    expect(decoded.opens.single.route.endsWith('/carpeta'), isTrue);
    expect(decoded.fields['fields.nie'], 'Y9736943E');
    expect(decodeAiChatPayload('jen text').text, 'jen text');
  });

  test('odkaz z přepisu otevře šanon bloku, ne jen desky', () {
    const open = AiChatOpen(
      clienteId: '11111111-1111-1111-1111-111111111111',
      label: 'escritura.pdf',
      carpeta: true,
      bloqueKey: 'escritura',
    );
    expect(open.route.endsWith('/carpeta/escritura'), isTrue);
  });

  test('jméno u titulare otevře desku, ne vypnuté escritura', () {
    const open = AiChatOpen(
      clienteId: '11111111-1111-1111-1111-111111111111',
      label: 'Petr Sokol',
      carpeta: true,
      bloqueKey: 'escritura',
    );
    expect(open.opensFolderDesk, isTrue);
    expect(open.route.endsWith('/carpeta'), isTrue);
    expect(open.route.endsWith('/carpeta/escritura'), isFalse);
  });

  test('id klienta z cesty kanceláře, ne z /carpeta', () {
    expect(
      clienteIdFromOfficePath(
        '/clientes/11111111-1111-1111-1111-111111111111/carpeta',
      ),
      '11111111-1111-1111-1111-111111111111',
    );
    expect(clienteIdFromOfficePath('/clientes'), isNull);
    expect(clienteIdFromOfficePath('/inbox'), isNull);
  });

  test('albums z RPC jsou seznam klíčů, prázdné pole je hromada', () {
    expect(jsonStringList(['luz', 'escritura']), ['luz', 'escritura']);
    expect(jsonStringList(<Object?>[]), isEmpty);
    expect(jsonStringList(null), isEmpty);
  });

  test('řádky z DB se čtou, hard-delete v nich není', () {
    final rows = [
      {
        'id': 'm1',
        'role': 'user',
        'content': 'Petr',
        'created_at': '2026-09-12T12:00:00Z',
      },
      {
        'id': 'm2',
        'role': 'assistant',
        'content': 'Nalezení klienti',
        'created_at': '2026-09-12T12:00:01Z',
      },
    ];
    final messages = parseAiChatMessages(rows);
    expect(messages, hasLength(2));
    expect(messages.first.fromUser, isTrue);
    expect(parseAiChatMessage({'role': 'system'}), isNull);
  });

  test('nejnovější zpráva je u vstupu, historie nahoru', () {
    expect(aiChatLatestFirstIndex(3, 0), 2);
    expect(aiChatLatestFirstIndex(3, 2), 0);
  });

  test('MIME z přípony rozliší PDF od fotky', () {
    expect(mimeForOfficeFile('nie.pdf'), 'application/pdf');
    expect(mimeForOfficeFile('pas.jpeg'), 'image/jpeg');
  });
}
