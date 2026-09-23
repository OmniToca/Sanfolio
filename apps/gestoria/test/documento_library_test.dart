import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/carpeta/documento_library.dart';
import 'package:gestoria_os/features/carpeta/stoh.dart';

void main() {
  test('album cizího bytu nejde, prázdná finca ano', () {
    expect(
      placementFitsInmueble(paperInmuebleId: 'a', bloqueInmuebleId: 'a'),
      isTrue,
    );
    expect(
      placementFitsInmueble(paperInmuebleId: 'a', bloqueInmuebleId: 'b'),
      isFalse,
    );
    expect(
      placementFitsInmueble(paperInmuebleId: null, bloqueInmuebleId: 'b'),
      isTrue,
    );
  });

  test('změna bytu sundá jen alba druhého bytu', () {
    final drop = placementsToDropOnInmuebleChange(
      newInmuebleId: 'a',
      placementBloqueInmueble: {
        'luz-a': 'a',
        'luz-b': 'b',
        'nie': null,
      },
    );
    expect(drop, ['luz-b']);
  });

  test('stejné bajty jsou duplicita dřív než název', () {
    const live = [
      LibraryPaperHint(
        id: '1',
        originalName: 'a.pdf',
        contentSha256: 'aaa',
      ),
    ];
    expect(
      matchDocumentoDuplicate(
        originalName: 'b.pdf',
        contentSha256: 'aaa',
        live: live,
      ),
      DocumentoDupKind.bytes,
    );
    expect(
      matchDocumentoDuplicate(
        originalName: 'A.PDF',
        contentSha256: 'bbb',
        live: live,
      ),
      DocumentoDupKind.name,
    );
  });

  test('stejná faktura i při jiném názvu souboru', () {
    const live = [
      LibraryPaperHint(
        id: '1',
        originalName: 'hidraqua.pdf',
        invoiceNo: 'F-1',
        period: '2024-01',
        amount: '188.85',
      ),
    ];
    expect(
      matchDocumentoDuplicate(
        originalName: 'scan2.pdf',
        invoiceNo: 'F-1',
        period: '2024-01',
        amount: '188.85',
        live: live,
      ),
      DocumentoDupKind.invoice,
    );
    expect(
      matchDocumentoDuplicate(
        originalName: 'scan2.pdf',
        invoiceNo: 'F-2',
        period: '2024-01',
        amount: '188.85',
        live: live,
      ),
      isNull,
    );
  });

  test('jeden byt přiřadí finca papír, DNI ne, dva byty bez adresy ne', () {
    const one = [LibraryInmueble(id: 'i1', direccion: 'Calle Sol 1')];
    const two = [
      LibraryInmueble(id: 'i1', direccion: 'Calle Sol 1'),
      LibraryInmueble(id: 'i2', direccion: 'Calle Luna 2'),
    ];
    expect(
      guessDocumentoInmueble(proposedBloque: 'luz', properties: one),
      'i1',
    );
    expect(
      guessDocumentoInmueble(proposedBloque: 'cliente_snapshot', properties: one),
      isNull,
    );
    expect(
      guessDocumentoInmueble(proposedBloque: 'luz', properties: two),
      isNull,
    );
    expect(
      guessDocumentoInmueble(
        proposedBloque: 'luz',
        properties: two,
        address: 'Calle Luna 2, Alicante',
      ),
      'i2',
    );
    expect(
      guessDocumentoInmueble(
        proposedBloque: 'suma',
        properties: const [
          LibraryInmueble(
            id: 'i1',
            direccion: 'Plaza Tolosa',
            catastral: '4244203YH0244S0003RX',
          ),
          LibraryInmueble(
            id: 'i2',
            direccion: 'C/ Dr. Luis Rivera 14',
            catastral: '1111111YH0111S0001AA',
          ),
        ],
        address: 'AV SAN FULGENCIO-MARINA 3',
        catastral: '4244203YH0244S0003RX',
      ),
      'i1',
    );
    expect(
      guessDocumentoInmueble(
        proposedBloque: 'suma',
        properties: const [
          LibraryInmueble(id: 'i1', direccion: 'Plaza Tolosa'),
        ],
        address: 'AV SAN FULGENCIO-MARINA 3',
        catastral: '4244203YH0244S0003RX',
      ),
      isNull,
    );
  });

  test('hromada nespouští finca banner u DNI, IBI s cizím katastrem ano', () {
    const one = [LibraryInmueble(id: 'i1', direccion: 'Plaza Tolosa')];
    expect(
      unmatchedFincaHint(
        papers: const [
          FincaPaperSignal(
            id: 'dni',
            bloqueKey: 'cliente_snapshot',
            address: 'Jicin',
          ),
        ],
        properties: one,
      ),
      isNull,
    );
    final hint = unmatchedFincaHint(
      papers: const [
        FincaPaperSignal(
          id: 'ibi',
          bloqueKey: 'suma',
          address: 'AV SAN FULGENCIO-MARINA 3',
          catastral: '4244203YH0244S0003RX',
        ),
        FincaPaperSignal(
          id: 'ibi2',
          bloqueKey: 'suma',
          address: 'AV SAN FULGENCIO-MARINA 3',
          catastral: '4244203YH0244S0003RX',
        ),
      ],
      properties: one,
    );
    expect(hint, isNotNull);
    expect(hint!.documentIds, ['ibi', 'ibi2']);
    expect(hint.catastral, '4244203YH0244S0003RX');
  });

  test('hromada se seskupí podle návrhu, mail a neznámé na konci', () {
    expect(pileGroupKey(proposedBloque: 'luz'), 'luz');
    expect(
      pileGroupKey(proposedBloque: '', originalName: 'gmail_print.pdf'),
      'mail',
    );
    expect(pileGroupKey(proposedBloque: ''), 'unknown');
    expect(
      pileGroupOrder(['unknown', 'luz', 'mail', 'agua']),
      ['agua', 'luz', 'mail', 'unknown'],
    );
  });

  test('nejistý návrh se nezařadí samo', () {
    expect(isConfidentStohProposal(const StohProposal()), isFalse);
    expect(
      isConfidentStohProposal(
        const StohProposal(bloqueKey: 'luz', tipo: 'factura_luz'),
      ),
      isTrue,
    );
  });

  test('stejné bajty mají stejný hash', () {
    expect(
      documentoContentSha256([1, 2, 3]),
      documentoContentSha256([1, 2, 3]),
    );
    expect(
      documentoContentSha256([1, 2, 3]),
      isNot(documentoContentSha256([1, 2, 4])),
    );
  });

  test('do alba z hromady jen papír, který v albu ještě není', () {
    expect(paperEligibleForAlbum(const [], 'escritura'), isTrue);
    expect(paperEligibleForAlbum(const ['luz'], 'escritura'), isTrue);
    expect(paperEligibleForAlbum(const ['escritura'], 'escritura'), isFalse);
  });

  test('spojit jen 2–20 JPG/PNG, ne PDF', () {
    expect(
      libraryMergeBlockReason(count: 1, allImages: true),
      'stoh.mergeMin',
    );
    expect(
      libraryMergeBlockReason(count: 2, allImages: false),
      'stoh.mergeNeedPhotos',
    );
    expect(
      libraryMergeBlockReason(count: 21, allImages: true),
      'stoh.mergeTooMany',
    );
    expect(libraryMergeBlockReason(count: 8, allImages: true), isNull);
    expect(isLibraryMergeImageName('a.jpg'), isTrue);
    expect(isLibraryMergeImageName('a.PDF'), isFalse);
    expect(isLibraryMergeImageName('file', 'x/stoh/a.png'), isTrue);
  });
}
