import 'package:flutter_test/flutter_test.dart';
import 'package:gestoria_os/features/carpeta/office_paper_memory.dart';
import 'package:gestoria_os/features/carpeta/stoh.dart';

void main() {
  test('dva blízké IBI z kanceláře zařadí další recibo', () {
    final office = officeClassifyConsensus([
      const OfficePaperExample(
        bloqueKey: 'suma',
        tipo: 'recibo_ibi',
        source: 'human',
        title: 'RECIBO IBI / SUMA',
        filledKeys: ['fields.period', 'fields.sumaId'],
        dist: 0.21,
      ),
      const OfficePaperExample(
        bloqueKey: 'suma',
        tipo: 'recibo_ibi',
        source: 'ai',
        title: 'IBI ejercicio 2024',
        dist: 0.33,
      ),
    ]);
    expect(office?.bloqueKey, 'suma');
    expect(office?.tipo, 'recibo_ibi');
    expect(
      classifyStohPaper(
        originalName: 'scan_01.pdf',
        bodyText: 'Objeto 6949519 Ejercicio 2024 Referencia catastral',
        office: office,
      ).bloqueKey,
      'suma',
    );
  });

  test('jeden vzdálený vzor nestačí, jistý titul listiny má přednost', () {
    expect(
      officeClassifyConsensus([
        const OfficePaperExample(
          bloqueKey: 'suma',
          tipo: 'recibo_ibi',
          source: 'human',
          dist: 0.40,
        ),
      ]),
      isNull,
    );
    expect(
      classifyStohPaper(
        originalName: 'scan.pdf',
        bodyText: 'ESCRITURA DE COMPRAVENTA Ante mí, Notario',
        office: const StohProposal(bloqueKey: 'suma', tipo: 'recibo_ibi'),
      ).bloqueKey,
      'escritura',
    );
  });

  test('prompt vzorů smaže NIE jiného klienta', () {
    final text = officeExamplesPrompt([
      const OfficePaperExample(
        bloqueKey: 'suma',
        tipo: 'recibo_ibi',
        source: 'human',
        title: 'Recibo IBI NIE Y9908856X Renata',
        caption: 'poslat na ana@test.com',
        filledKeys: ['fields.period', 'fields.nie'],
        dist: 0.12,
      ),
    ]);
    expect(text, contains('album=suma'));
    expect(text, contains('[NIE]'));
    expect(text, contains('[email]'));
    expect(text, isNot(contains('Y9908856X')));
    expect(text, isNot(contains('ana@test.com')));
  });
}
