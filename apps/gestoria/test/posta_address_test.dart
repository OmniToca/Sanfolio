import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/mensajes/mensaje_providers.dart';
import 'package:gestoria_os/features/posta/posta_address.dart';
import 'package:gestoria_os/features/posta/posta_providers.dart';
import 'package:gestoria_os/features/posta/posta_timeline.dart';

void main() {
  test('extractEmailAddress bere úhlové i holé adresy', () {
    expect(
      extractEmailAddress('Ana García <ana@example.com>'),
      'ana@example.com',
    );
    expect(extractEmailAddress('ANA@Example.com'), 'ana@example.com');
    expect(extractEmailAddress('není mail'), isNull);
  });

  test('postaReplyTo přidá UUID klienta za ingest local', () {
    const cliente = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    expect(
      postaReplyTo(
        ingestAddress: 'pjarka12@inbound.sanfolio.app',
        clienteId: cliente,
      ),
      'pjarka12+$cliente@inbound.sanfolio.app',
    );
  });

  test('postaPlusClienteId čte jen platné UUID za plusem', () {
    const cliente = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    expect(
      postaPlusClienteId('pjarka12+$cliente@inbound.sanfolio.app'),
      cliente,
    );
    expect(postaPlusClienteId('pjarka12+not-uuid@inbound.sanfolio.app'), isNull);
    expect(postaPlusClienteId('pjarka12@inbound.sanfolio.app'), isNull);
  });

  test('filtr pošty schová ignored a oddělí přílohy', () {
    final unassigned = PostaMessage(
      id: '1',
      fromAddress: 'a@b.cz',
      receivedAt: DateTime.utc(2026, 9, 15),
      status: 'unassigned',
      attachments: const [
        PostaAttachment(
          id: 'x',
          filename: 'luz.pdf',
          storagePath: 't/posta/1/luz.pdf',
        ),
      ],
    );
    final assigned = PostaMessage(
      id: '2',
      fromAddress: 'a@b.cz',
      receivedAt: DateTime.utc(2026, 9, 15),
      status: 'assigned',
      clienteId: 'c',
    );
    final ignored = PostaMessage(
      id: '3',
      fromAddress: 'spam@b.cz',
      receivedAt: DateTime.utc(2026, 9, 15),
      status: 'ignored',
    );
    expect(matchesPostaFilter(unassigned, 'unassigned'), isTrue);
    expect(matchesPostaFilter(unassigned, 'attachments'), isTrue);
    expect(matchesPostaFilter(assigned, 'unassigned'), isFalse);
    expect(matchesPostaFilter(assigned, 'assigned'), isTrue);
    expect(matchesPostaFilter(ignored, 'all'), isFalse);
    final unfiled = PostaMessage(
      id: '4',
      fromAddress: 'a@b.cz',
      receivedAt: DateTime.utc(2026, 9, 15),
      status: 'assigned',
      clienteId: 'c',
      attachments: const [
        PostaAttachment(
          id: 'y',
          filename: 'nie.pdf',
          storagePath: 't/posta/4/nie.pdf',
        ),
      ],
    );
    expect(matchesPostaFilter(unfiled, 'unfiled'), isTrue);
    expect(matchesPostaFilter(assigned, 'unfiled'), isFalse);
  });

  test('karta slučuje mail od klienta a výzvu kanceláře, WhatsApp ne', () {
    final inbound = PostaMessage(
      id: 'in',
      fromAddress: 'sokolpetr87@gmail.com',
      fromName: 'Petr Sokol',
      subject: 'NIE scan',
      receivedAt: DateTime.utc(2026, 9, 15, 10),
      status: 'assigned',
      clienteId: 'c',
    );
    final emailOut = ClienteMensaje(
      id: 'out',
      status: 'sent',
      cuerpo: 'Hola',
      localeOriginal: 'es',
      translations: const {},
      asunto: 'Documentación',
      canal: 'email',
      sentAt: DateTime.utc(2026, 9, 16, 9),
    );
    final wa = ClienteMensaje(
      id: 'wa',
      status: 'sent',
      cuerpo: 'Hola',
      localeOriginal: 'es',
      translations: const {},
      canal: 'whatsapp',
      sentAt: DateTime.utc(2026, 9, 17),
    );
    final merged = mergeClienteMail(
      inbound: [inbound],
      outbound: [emailOut, wa],
    );
    expect(merged, hasLength(2));
    expect(merged.first.id, 'out');
    expect(merged.first.direction, ClienteMailDirection.outbound);
    expect(merged.last.id, 'in');
    expect(merged.last.direction, ClienteMailDirection.inbound);
  });
}
