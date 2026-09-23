import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/carpeta/carpeta_controller.dart';
import 'package:gestoria_os/features/carpeta/documento_library.dart';
import 'package:gestoria_os/features/carpeta/library_view.dart';
import 'package:gestoria_os/features/carpeta/stoh_queue.dart';

void main() {
  CarpetaDocumento paper({
    required String id,
    List<String> albums = const [],
    String name = 'a.pdf',
    String sha = '',
    String tipo = 'factura_luz',
    Map<String, String> extracted = const {},
    String? bodyText,
  }) {
    return CarpetaDocumento(
      id: id,
      tipo: tipo,
      storagePath: 't/c/stoh/$id.pdf',
      originalName: name,
      extracted: extracted,
      bodyText: bodyText,
      contentSha256: sha,
      createdAt: DateTime(2026, 9, 23),
      albumKeys: albums,
    );
  }

  test('hromada se filtruje a seskupí, pohled bere částku ne dump', () {
    final papers = buildLibraryPapers(
      documents: [
        paper(id: '1', name: 'hidraqua.pdf'),
        paper(
          id: '2',
          albums: ['luz'],
          name: 'luz.pdf',
          extracted: const {'fields.amount': '88,50'},
        ),
        paper(
          id: '3',
          sha: 'aaa',
          name: 'fac-a.pdf',
          extracted: const {'fields.invoiceNo': '1', 'fields.amount': '10'},
        ),
        paper(
          id: '4',
          sha: 'aaa',
          name: 'fac-b.pdf',
          extracted: const {'fields.invoiceNo': '1', 'fields.amount': '10'},
        ),
      ],
      drafts: const <StohQueueRow>[],
      inmuebles: const [],
    );
    expect(
      filterLibraryPapers(papers: papers, scope: LibraryScope.pile).length,
      3,
    );
    expect(
      filterLibraryPapers(papers: papers, scope: LibraryScope.placed).length,
      1,
    );
    expect(
      filterLibraryPapers(papers: papers, scope: LibraryScope.duplicates).length,
      2,
    );
    final glance = libraryGlanceEntries(
      const {
        'fields.amount': '88,50',
        'fields.foo': 'x',
        'fields.holder': 'Renata',
        'fields.company': 'Gana Energía',
      },
    );
    expect(glance.map((e) => e.key).toList(), [
      'fields.amount',
      'fields.company',
      'fields.holder',
    ]);
    expect(
      libraryFincaLabel(
        const LibraryInmueble(id: '569c687f-8f74-471b-a681-be7b38867d6b'),
      ),
      isEmpty,
    );
    expect(
      libraryFincaLabel(
        const LibraryInmueble(
          id: '569c687f-8f74-471b-a681-be7b38867d6b',
          catastral: '8443304XH9184S0025KY',
        ),
      ),
      '8443304XH9184S0025KY',
    );
  });

  test('deska čte papír z junction, stejný PDF na dvou albech', () {
    final p = paper(id: '1', albums: ['luz', 'escritura'], name: 'luz.pdf');
    final map = documentsByAlbumBloque(
      papers: [p],
      placementsByDocId: {
        '1': const [
          AlbumHit(bloqueId: 'b-luz', tipo: 'factura_luz'),
          AlbumHit(bloqueId: 'b-esc', tipo: 'copia_escritura'),
        ],
      },
    );
    expect(map['b-luz']!.single.id, '1');
    expect(map['b-luz']!.single.tipo, 'factura_luz');
    expect(map['b-esc']!.single.id, '1');
    expect(map['b-esc']!.single.tipo, 'copia_escritura');
    expect(
      documentsByAlbumBloque(
        papers: [p],
        placementsByDocId: const {},
      ),
      isEmpty,
    );
  });

  test('pohled DNI je věta, ne dump polí, rok narození není čip', () {
    final papers = buildLibraryPapers(
      documents: [
        paper(
          id: '1',
          tipo: 'dni_nie',
          name: 'ID y NIE Renata.pdf',
          extracted: const {
            'fields.nie': 'Y9908856X',
            'fields.nombre': 'Renata Sušičová',
            'fields.date': '1972-03-28',
          },
        ),
      ],
      drafts: const <StohQueueRow>[],
      inmuebles: const [],
    );
    final row = papers.single;
    expect(libraryPaperTipo(row), 'dni_nie');
    expect(libraryShowsYearChip(row), isFalse);
    final summary = libraryPaperAutoSummary(
      row,
      tr: (key, {named = const {}}) =>
          named.isEmpty ? key : named.values.join(),
    );
    expect(summary, contains('Y9908856X'));
    expect(summary, contains('Renata Sušičová'));
    expect(summary, contains('28-03-1972'));
    expect(summary, isNot(contains('fields.nie')));
  });

  test('faktura má čip roku z vystavení', () {
    final papers = buildLibraryPapers(
      documents: [
        paper(
          id: '2',
          name: 'luz.pdf',
          extracted: const {
            'fields.company': 'Gana Energía',
            'fields.amount': '88,50',
            'fields.issued': '2026-08-01',
          },
        ),
      ],
      drafts: const <StohQueueRow>[],
      inmuebles: const [],
    );
    expect(libraryShowsYearChip(papers.single), isTrue);
    expect(libraryPaperYear(papers.single), 2026);
  });

  test('nadpis z první strany je v pohledu, ne dump NIE', () {
    final papers = buildLibraryPapers(
      documents: [
        paper(
          id: 'esc',
          tipo: 'other',
          name: 'scan_01.pdf',
          extracted: const {
            'fields.nie': 'Y9908856X',
            'fields.nombre': 'Renata Sušičová',
            'fields.lawyer': 'GARCIA-BRAVO',
          },
        ),
      ],
      drafts: [
        StohQueueRow(
          document: paper(id: 'esc', tipo: 'other', name: 'scan_01.pdf'),
          draftId: 'd1',
          fields: const {
            'body_text':
                '--- Strana 1/45 ---\nESCRITURA DE COMPRAVENTA\nAnte mí, Notario',
            'fields.nie': 'Y9908856X',
          },
        ),
      ],
      inmuebles: const [],
    );
    // draft se páruje podle storage_path; helper má stejnou cestu
    final row = papers.single;
    expect(row.proposal.bloqueKey, 'escritura');
    final summary = libraryPaperAutoSummary(
      row,
      tr: (key, {named = const {}}) =>
          named.isEmpty ? key : named.values.join(),
    );
    expect(summary, contains('ESCRITURA DE COMPRAVENTA'));
  });

  test('Guardar pozná papír na desce podle extracted, hromada ne', () {
    expect(
      libraryPaperOnDesk(
        LibraryPaper(
          document: paper(
            id: '1',
            extracted: const {'fields.nie': 'Y9908856X'},
          ),
        ),
      ),
      isTrue,
    );
    expect(
      libraryPaperOnDesk(LibraryPaper(document: paper(id: '2'))),
      isFalse,
    );
  });

  test('CTA bancaria ukáže IBAN, ne telefon z číslic za ES', () {
    const sheet = '''
NOMBRE DE LA CUENTA/ACCOUNT NAME: LA MARINA SERVICES INTERNATIONAL
IBAN: ES96 2100 9143 9413 0049 8086
BIC: CAIXESBBXXX
''';
    final papers = buildLibraryPapers(
      documents: [
        paper(
          id: 'cta',
          tipo: 'other',
          name: 'Cta bancaria agencia.pdf',
          extracted: const {'fields.tel': '9621009143941'},
          bodyText: sheet,
        ),
      ],
      drafts: const <StohQueueRow>[],
      inmuebles: const [],
    );
    final row = papers.single;
    expect(libraryPaperTipo(row), 'justificante_iban');
    expect(row.glanceFields['fields.iban'], 'ES9621009143941300498086');
    expect(row.glanceFields.containsKey('fields.tel'), isFalse);
    final summary = libraryPaperAutoSummary(
      row,
      tr: (key, {named = const {}}) =>
          named.isEmpty ? key : named.values.join(),
    );
    expect(summary, contains('ES96 2100 9143 9413 0049 8086'));
    expect(summary, isNot(contains('9621009143941')));
  });
}
