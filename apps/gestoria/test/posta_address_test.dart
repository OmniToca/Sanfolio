import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/posta/posta_address.dart';
import 'package:gestoria_os/features/posta/posta_providers.dart';

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
  });
}
