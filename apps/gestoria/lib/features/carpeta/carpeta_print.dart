import '../../core/money/cents.dart';
import 'bloque_template.dart';
import 'carpeta_controller.dart';

/// List 1 = před notářem (identita, IBI, dodávky). List 2 = notář a po.
const kCarpetaPrintSheet1Keys = <String>[
  'cliente_snapshot',
  'nie_tramite',
  'poder',
  'suma',
  'agua',
  'luz',
  'gaz',
  'comunidad',
];

const kCarpetaPrintSheet2Keys = <String>[
  'escritura',
  'plusvalia',
  'seguro',
  'provision_factura',
  'alarma',
];

int carpetaPrintSheetFor(String bloqueKey) {
  if (kCarpetaPrintSheet1Keys.contains(bloqueKey)) return 1;
  return 2;
}

String carpetaPrintStatusI18nKey(String dbStatus) {
  return switch (dbStatus) {
    'off' => 'blockStatus.off',
    'missing_data' => 'blockStatus.missingData',
    'missing_document' => 'blockStatus.missingDocument',
    'done' => 'blockStatus.done',
    _ => 'blockStatus.watching',
  };
}

class CarpetaPrintField {
  const CarpetaPrintField({required this.label, required this.value});

  final String label;
  final String value;
}

class CarpetaPrintDoc {
  const CarpetaPrintDoc({required this.label, required this.have});

  final String label;
  final bool have;
}

class CarpetaPrintBloque {
  const CarpetaPrintBloque({
    required this.key,
    required this.title,
    required this.status,
    required this.fields,
    required this.docs,
  });

  final String key;
  final String title;
  final String status;
  final List<CarpetaPrintField> fields;
  final List<CarpetaPrintDoc> docs;
}

class CarpetaPrintTitular {
  const CarpetaPrintTitular({
    required this.nombre,
    required this.nie,
    required this.lado,
    required this.share,
  });

  final String nombre;
  final String nie;
  final String lado;
  final String share;
}

/// Data dvou listů. Popisky už přeložené — HTML není i18n runtime.
class CarpetaPrintModel {
  const CarpetaPrintModel({
    required this.officeName,
    required this.clienteNombre,
    required this.direccion,
    required this.nie,
    required this.printedOn,
    required this.sheet1Title,
    required this.sheet2Title,
    required this.sheet1,
    required this.sheet2,
    required this.offLabels,
    required this.titulares,
    required this.printLabel,
    required this.offHeading,
    required this.titularesHeading,
    required this.docHave,
    required this.docMissing,
  });

  final String officeName;
  final String clienteNombre;
  final String direccion;
  final String nie;
  final String printedOn;
  final String sheet1Title;
  final String sheet2Title;
  final List<CarpetaPrintBloque> sheet1;
  final List<CarpetaPrintBloque> sheet2;
  final List<String> offLabels;
  final List<CarpetaPrintTitular> titulares;
  final String printLabel;
  final String offHeading;
  final String titularesHeading;
  final String docHave;
  final String docMissing;
}

CarpetaPrintModel buildCarpetaPrintModel({
  required CarpetaView view,
  required List<BloqueTemplate> templates,
  required String officeName,
  required String printedOn,
  required String Function(String key) bloqueLabel,
  required String Function(String fieldKey) fieldLabel,
  required String Function(String tipo) docLabel,
  required String Function(String dbStatus) statusLabel,
  required String sheet1Title,
  required String sheet2Title,
  required String printLabel,
  required String offHeading,
  required String titularesHeading,
  required String docHave,
  required String docMissing,
  required String ladoComprador,
  required String ladoVendedor,
  required String nombreLabel,
}) {
  final sheet1 = <CarpetaPrintBloque>[];
  final sheet2 = <CarpetaPrintBloque>[];
  final offLabels = <String>[];
  for (final template in templates) {
    final state = view.bloques[template.key] ?? const BloqueState(enabled: false);
    if (!state.enabled) {
      offLabels.add(bloqueLabel(template.key));
      continue;
    }
    final block = _bloque(
      view: view,
      template: template,
      state: state,
      bloqueLabel: bloqueLabel,
      fieldLabel: fieldLabel,
      docLabel: docLabel,
      statusLabel: statusLabel,
      nombreLabel: nombreLabel,
    );
    if (carpetaPrintSheetFor(template.key) == 1) {
      sheet1.add(block);
    } else {
      sheet2.add(block);
    }
  }
  // Čas papíru, ne slot_order z desky.
  sheet1.sort(
    (a, b) => _sheetIndex(kCarpetaPrintSheet1Keys, a.key)
        .compareTo(_sheetIndex(kCarpetaPrintSheet1Keys, b.key)),
  );
  sheet2.sort(
    (a, b) => _sheetIndex(kCarpetaPrintSheet2Keys, a.key)
        .compareTo(_sheetIndex(kCarpetaPrintSheet2Keys, b.key)),
  );
  final titulares = [
    for (final t in view.titulares)
      CarpetaPrintTitular(
        nombre: t.nombre,
        nie: t.nieRaw,
        lado: t.isComprador ? ladoComprador : ladoVendedor,
        share: '${(t.cuotaBps / 100).toStringAsFixed(2)} %',
      ),
  ];
  final snapshot = view.bloques['cliente_snapshot'];
  return CarpetaPrintModel(
    officeName: officeName,
    clienteNombre: view.nombre,
    direccion: view.inmuebleDireccion ?? '',
    nie: snapshot?.values['fields.nie'] ?? '',
    printedOn: printedOn,
    sheet1Title: sheet1Title,
    sheet2Title: sheet2Title,
    sheet1: sheet1,
    sheet2: sheet2,
    offLabels: offLabels,
    titulares: titulares,
    printLabel: printLabel,
    offHeading: offHeading,
    titularesHeading: titularesHeading,
    docHave: docHave,
    docMissing: docMissing,
  );
}

CarpetaPrintBloque _bloque({
  required CarpetaView view,
  required BloqueTemplate template,
  required BloqueState state,
  required String Function(String key) bloqueLabel,
  required String Function(String fieldKey) fieldLabel,
  required String Function(String tipo) docLabel,
  required String Function(String dbStatus) statusLabel,
  required String nombreLabel,
}) {
  final fields = <CarpetaPrintField>[];
  if (template.key == 'cliente_snapshot' && view.nombre.trim().isNotEmpty) {
    fields.add(CarpetaPrintField(label: nombreLabel, value: view.nombre.trim()));
  }
  for (final key in template.fieldKeys) {
    fields.add(
      CarpetaPrintField(
        label: fieldLabel(key),
        value: _displayField(key, state.values[key] ?? ''),
      ),
    );
  }
  final have = {for (final d in state.documents) d.tipo};
  final docs = [
    for (final tipo in template.requiredDocTypes)
      CarpetaPrintDoc(label: docLabel(tipo), have: have.contains(tipo)),
  ];
  return CarpetaPrintBloque(
    key: template.key,
    title: bloqueLabel(template.key),
    status: statusLabel(state.dbStatus),
    fields: fields,
    docs: docs,
  );
}

int _sheetIndex(List<String> keys, String key) {
  final i = keys.indexOf(key);
  return i < 0 ? keys.length : i;
}

String _displayField(String field, String raw) {
  if (field == 'fields.received' ||
      field == 'fields.invoiced' ||
      field == 'fields.remaining') {
    if (raw.trim().isEmpty) return '';
    return '${formatCents(centsFromStored(raw))} €';
  }
  return raw.trim();
}

String carpetaPrintHtml(CarpetaPrintModel model) {
  final title = model.clienteNombre.isEmpty
      ? model.officeName
      : model.clienteNombre;
  return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<title>${_esc(title)}</title>
<style>
  @page { size: A4; margin: 12mm; }
  * { box-sizing: border-box; }
  body {
    font-family: "Plus Jakarta Sans", "Segoe UI", Helvetica, Arial, sans-serif;
    color: #161412; margin: 0; background: #fff;
  }
  .toolbar { display: flex; justify-content: flex-end; margin-bottom: 10px; }
  .toolbar button {
    font: inherit; background: #1B5F59; color: #F7FFFE; border: 0;
    border-radius: 8px; padding: 8px 14px; cursor: pointer;
  }
  .page { page-break-after: always; }
  .page:last-child { page-break-after: auto; }
  .mast {
    display: flex; justify-content: space-between; align-items: flex-end;
    gap: 16px; padding-bottom: 8px; border-bottom: 2px solid #1B5F59;
    margin-bottom: 12px;
  }
  .brand { font-size: 18px; font-weight: 700; color: #1B5F59; }
  .who { font-size: 20px; font-weight: 700; letter-spacing: -0.02em; }
  .meta { color: #3F4A48; font-size: 12px; margin-top: 4px; }
  .sheet-kicker {
    font-size: 11px; font-weight: 600; letter-spacing: 0.08em;
    text-transform: uppercase; color: #1B5F59; margin: 0 0 10px;
  }
  .block {
    border: 1px solid #DFD8CC; border-radius: 6px; padding: 10px 12px;
    margin-bottom: 8px; break-inside: avoid;
  }
  .block h2 {
    font-size: 13px; margin: 0 0 6px; display: flex;
    justify-content: space-between; gap: 12px;
  }
  .st { font-size: 11px; font-weight: 600; color: #1B5F59; }
  .row {
    display: grid; grid-template-columns: 38% 1fr; gap: 8px;
    padding: 3px 0; border-bottom: 1px solid #EDE8DF; font-size: 12px;
  }
  .row:last-child { border-bottom: 0; }
  .lab { color: #3F4A48; }
  .docs { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; }
  .chip {
    font-size: 10px; padding: 2px 6px; border-radius: 4px;
    border: 1px solid #DFD8CC;
  }
  .chip.ok { background: #D7EBE8; border-color: #1B5F59; }
  .off { font-size: 12px; color: #6B645C; margin-top: 10px; }
  @media print {
    .toolbar { display: none !important; }
  }
</style>
</head>
<body>
<div class="toolbar"><button type="button" onclick="window.print()">${_esc(model.printLabel)}</button></div>
${_page(model, sheet: 1)}
${_page(model, sheet: 2)}
<script>
window.addEventListener('load', function () {
  setTimeout(function () { window.print(); }, 280);
});
</script>
</body>
</html>
''';
}

String _page(CarpetaPrintModel model, {required int sheet}) {
  final blocks = sheet == 1 ? model.sheet1 : model.sheet2;
  final kicker = sheet == 1 ? model.sheet1Title : model.sheet2Title;
  final extra = StringBuffer();
  if (sheet == 2 && model.titulares.isNotEmpty) {
    extra.write('<div class="block"><h2>${_esc(model.titularesHeading)}</h2>');
    for (final t in model.titulares) {
      extra.write(
        '<div class="row"><span class="lab">${_esc(t.lado)}</span>'
        '<span>${_esc(t.nombre)} · ${_esc(t.nie)} · ${_esc(t.share)}</span></div>',
      );
    }
    extra.write('</div>');
  }
  if (sheet == 2 && model.offLabels.isNotEmpty) {
    extra.write(
      '<div class="off">${_esc(model.offHeading)}: ${_esc(model.offLabels.join(' · '))}</div>',
    );
  }
  final nie = model.nie.trim();
  final dir = model.direccion.trim();
  return '''
<div class="page">
  <div class="mast">
    <div>
      <div class="brand">${_esc(model.officeName)}</div>
      <div class="who">${_esc(model.clienteNombre)}</div>
      <div class="meta">${_esc([
        if (nie.isNotEmpty) nie,
        if (dir.isNotEmpty) dir,
        model.printedOn,
      ].join(' · '))}</div>
    </div>
  </div>
  <div class="sheet-kicker">${_esc(kicker)}</div>
  ${blocks.map((b) => _blockHtml(b, model)).join()}
  $extra
</div>
''';
}

String _blockHtml(CarpetaPrintBloque block, CarpetaPrintModel model) {
  final rows = [
    for (final f in block.fields)
      '<div class="row"><span class="lab">${_esc(f.label)}</span>'
          '<span>${_esc(f.value.isEmpty ? '—' : f.value)}</span></div>',
  ].join();
  final docs = [
    for (final d in block.docs)
      '<span class="chip${d.have ? ' ok' : ''}">${_esc(d.label)} · ${_esc(d.have ? model.docHave : model.docMissing)}</span>',
  ].join();
  return '''
<div class="block">
  <h2>${_esc(block.title)}<span class="st">${_esc(block.status)}</span></h2>
  $rows
  ${docs.isEmpty ? '' : '<div class="docs">$docs</div>'}
</div>
''';
}

String _esc(String raw) {
  return raw
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
