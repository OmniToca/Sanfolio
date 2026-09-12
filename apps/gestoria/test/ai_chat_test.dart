import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/ai/ai_chat.dart';

void main() {
  test('panel je na širokém stole otevřený, dokud ho gestor neskryje', () {
    expect(
      aiPanelVisible(width: 1280, preference: null),
      isTrue,
    );
    expect(
      aiPanelVisible(width: 800, preference: null),
      isFalse,
    );
    expect(
      aiPanelVisible(width: 800, preference: true),
      isTrue,
    );
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
}
