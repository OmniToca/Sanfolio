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
    Map<String, String> extracted = const {},
  }) {
    return CarpetaDocumento(
      id: id,
      tipo: 'factura_luz',
      storagePath: 't/c/stoh/$id.pdf',
      originalName: name,
      extracted: extracted,
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
}
