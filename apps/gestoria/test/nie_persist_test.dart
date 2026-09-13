import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/core/identity/nie_persist.dart';

void main() {
  test('stejné číslo jako nie i dni je konflikt mezi kartami', () {
    expect(
      fiscalIdConflicts(
        normalized: 'Y9736943E',
        clienteId: 'monika',
        liveInTenant: const [
          LiveIdentifier(
            id: '1',
            kind: 'nie',
            valueNormalized: 'Y9736943E',
            clienteId: 'petr',
          ),
        ],
      ),
      isTrue,
    );
    expect(
      fiscalIdConflicts(
        normalized: 'Y9736943E',
        clienteId: 'petr',
        liveInTenant: const [
          LiveIdentifier(
            id: '1',
            kind: 'dni',
            valueNormalized: 'Y9736943E',
            clienteId: 'petr',
          ),
        ],
      ),
      isFalse,
    );
  });

  test('prázdné NIE smaže jen kind nie, pas nechá', () {
    final plan = planNiePersist(
      nieNormalized: '',
      liveOnCliente: const [
        LiveIdentifier(id: 'pas', kind: 'passport', valueNormalized: 'P123'),
        LiveIdentifier(id: 'nie', kind: 'nie', valueNormalized: 'Y9736943E'),
      ],
    );
    expect(plan.op, NiePersistOp.softDeleteNie);
    expect(plan.targetId, 'nie');

    final onlyPass = planNiePersist(
      nieNormalized: '',
      liveOnCliente: const [
        LiveIdentifier(id: 'pas', kind: 'passport', valueNormalized: 'P123'),
      ],
    );
    expect(onlyPass.op, NiePersistOp.none);
  });

  test('NIE pole nebere pas, když karta má i fiskální ID', () {
    expect(
      preferredFiscalRaw(const [
        IdentifierRaw(kind: 'passport', valueRaw: 'P123'),
        IdentifierRaw(kind: 'nie', valueRaw: 'Y9736943E'),
      ]),
      'Y9736943E',
    );
    expect(
      preferredFiscalRaw(const [
        IdentifierRaw(kind: 'passport', valueRaw: 'P123'),
      ]),
      isNull,
    );
    expect(
      preferredFiscalRawFromRows([
        {'kind': 'passport', 'value_raw': 'P123', 'deleted_at': null},
        {'kind': 'nie', 'value_raw': 'Y9736943E', 'deleted_at': null},
      ]),
      'Y9736943E',
    );
  });

  test('prázdné NIE při jen pasu nic nemaže, update sahá na nie', () {
    final inserted = planNiePersist(
      nieNormalized: 'Y9736943E',
      liveOnCliente: const [
        LiveIdentifier(id: 'pas', kind: 'passport', valueNormalized: 'P123'),
      ],
    );
    expect(inserted.op, NiePersistOp.insert);

    final updated = planNiePersist(
      nieNormalized: 'Y9737090P',
      liveOnCliente: const [
        LiveIdentifier(id: 'nie', kind: 'nie', valueNormalized: 'Y9736943E'),
        LiveIdentifier(id: 'pas', kind: 'passport', valueNormalized: 'P123'),
      ],
    );
    expect(updated.op, NiePersistOp.update);
    expect(updated.targetId, 'nie');
  });

  test('konflikt NIE vrátí pole na živé číslo karty, unique je 23505', () {
    expect(
      nieFieldAfterConflict(
        conflict: true,
        typedRaw: 'Y9737090P',
        liveOnCliente: const [
          LiveIdentifier(
            id: '1',
            kind: 'nie',
            valueNormalized: 'Y9736943E',
            valueRaw: 'Y-9736943-E',
          ),
        ],
      ),
      'Y-9736943-E',
    );
    expect(
      nieFieldAfterConflict(
        conflict: true,
        typedRaw: 'Y9737090P',
        liveOnCliente: const [],
      ),
      '',
    );
    expect(
      nieFieldAfterConflict(
        conflict: false,
        typedRaw: 'Y9737090P',
        liveOnCliente: const [],
      ),
      'Y9737090P',
    );
    expect(looksLikeUniqueConstraint('PostgrestException(code: 23505)'), isTrue);
    expect(looksLikeUniqueConstraint('network'), isFalse);
  });

  test('fokusované NIE po konfliktu se synchronizuje, jméno ne', () {
    expect(
      syncDeskFieldFromParent(fieldKey: 'fields.nie', focused: true),
      isTrue,
    );
    expect(
      syncDeskFieldFromParent(fieldKey: 'fields.nombre', focused: true),
      isFalse,
    );
    expect(
      syncDeskFieldFromParent(fieldKey: 'fields.nombre', focused: false),
      isTrue,
    );
  });

  test('prázdné NIE z identifikátorů přepíše vepsané číslo na desce', () {
    final desk = <String, String>{
      'fields.nie': 'Y9737090P',
      'fields.email': 'stary@x.cz',
    };
    overlayClienteSnapshot(
      desk: desk,
      live: const {
        'fields.nie': '',
        'fields.email': 'petr@x.cz',
      },
    );
    expect(desk['fields.nie'], '');
    expect(desk['fields.email'], 'petr@x.cz');
  });

  test('rozhodnutí NIE pozná cizí kartu, vlastní řádek nechá zapsat', () {
    final taken = decideNieSave(
      nieRaw: 'Y9737090P',
      nieNormalized: 'Y9737090P',
      clienteId: 'petr',
      liveOnCliente: const [
        LiveIdentifier(
          id: '1',
          kind: 'nie',
          valueNormalized: 'Y9736943E',
          clienteId: 'petr',
          valueRaw: 'Y-9736943-E',
        ),
      ],
      liveInTenant: const [
        LiveIdentifier(
          id: '2',
          kind: 'nie',
          valueNormalized: 'Y9737090P',
          clienteId: 'monika',
        ),
      ],
    );
    expect(taken.conflict, isTrue);
    expect(taken.keepNie, 'Y-9736943-E');
    final own = decideNieSave(
      nieRaw: 'Y9736943E',
      nieNormalized: 'Y9736943E',
      clienteId: 'petr',
      liveOnCliente: const [
        LiveIdentifier(
          id: '1',
          kind: 'nie',
          valueNormalized: 'Y9736943E',
          clienteId: 'petr',
        ),
      ],
      liveInTenant: const [
        LiveIdentifier(
          id: '1',
          kind: 'nie',
          valueNormalized: 'Y9736943E',
          clienteId: 'petr',
        ),
      ],
    );
    expect(own.conflict, isFalse);
    expect(own.plan.op, NiePersistOp.update);
  });
}
