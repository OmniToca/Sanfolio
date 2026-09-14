import '../../core/money/cents.dart';
import '../../core/time/office_date.dart';
import 'factura.dart';
import 'factura_lineas.dart';

/// A4 HTML tisk vystavené. Popisky jsou španělské úřední, ne staff locale.
String facturaEmitidaPrintHtml({
  required Factura factura,
  required String emisorNombre,
  required String emisorNif,
}) {
  final totals = totalsFromLineas([
    for (final raw in factura.lineas) FacturaLinea.fromJson(raw),
  ]);
  final lines = totals.lineas.isNotEmpty
      ? totals.lineas
      : [
          if (factura.totalCents > 0 || factura.baseCents > 0)
            FacturaLinea(
              descripcion: (factura.concepto ?? '').trim().isEmpty
                  ? 'Servicios'
                  : factura.concepto!.trim(),
              cantidad: 1,
              precioUnitarioCents: factura.baseCents,
              ivaBps: factura.ivaBps ?? 2100,
            ),
        ];
  final byRate = totals.lineas.isNotEmpty
      ? totals.byRate
      : [
          IvaBreakdown(
            ivaBps: factura.ivaBps ?? 2100,
            baseCents: factura.baseCents,
            ivaCents: factura.ivaCents,
          ),
        ];
  final total = totals.lineas.isNotEmpty ? totals.totalCents : factura.totalCents;
  final title = factura.isSimplificada ? 'FACTURA SIMPLIFICADA' : 'FACTURA';
  final qrSrc = factura.sifQrUrl ?? '';
  final qrImg = qrSrc.startsWith('data:image')
      ? '<img class="qr" alt="QR VeriFactu" src="${_esc(qrSrc)}"/>'
      : '';
  final lineRows = [
    for (final line in lines)
      '<tr>'
          '<td>${_esc(line.descripcion)}</td>'
          '<td class="num">${_esc(cantidadString(line.cantidad))}</td>'
          '<td class="num">${_esc(formatCents(line.precioUnitarioCents))}</td>'
          '<td class="num">${_esc(ivaRateLabel(line.ivaBps))}</td>'
          '<td class="num">${_esc(formatCents(line.baseCents))}</td>'
          '<td class="num">${_esc(formatCents(line.totalCents))}</td>'
          '</tr>',
  ].join();
  final taxRows = [
    for (final row in byRate)
      '<div class="sum-row">'
          '<span>Base ${_esc(ivaRateLabel(row.ivaBps))}</span>'
          '<span>${_esc(formatCents(row.baseCents))} €</span>'
          '</div>'
          '<div class="sum-row">'
          '<span>IVA ${_esc(ivaRateLabel(row.ivaBps))}</span>'
          '<span>${_esc(formatCents(row.ivaCents))} €</span>'
          '</div>',
  ].join();
  final destName = (factura.destinatarioNombre ?? '').trim();
  final dest = destName.isNotEmpty || factura.hasDestinatario
      ? '''
<div class="party dest">
  <h2>Destinatario</h2>
  <div class="name">${_esc(destName)}</div>
  ${factura.destinatarioDireccion == null ? '' : '<div>${_esc(factura.destinatarioDireccion!)}</div>'}
  ${factura.destinatarioNif == null ? '' : '<div class="ids">NIF ${_esc(factura.destinatarioNif!)}</div>'}
  ${factura.destinatarioEmail == null ? '' : '<div class="ids">${_esc(factura.destinatarioEmail!)}</div>'}
</div>'''
      : '''
<div class="party dest">
  <h2>Destinatario</h2>
  <div>—</div>
</div>''';
  final fecha = toDmyDate(factura.fecha) ?? factura.fecha ?? '—';
  final venc = factura.vencimiento == null
      ? '—'
      : (toDmyDate(factura.vencimiento) ?? factura.vencimiento!);
  final tipo = factura.isSimplificada ? 'F2 Simplificada' : 'F1 Completa';
  final pago = factura.formaPago == null ? '—' : _pagoEs(factura.formaPago!);
  final concepto = (factura.concepto ?? '').trim();
  final notas = (factura.notas ?? '').trim();
  final firstLine = lines.isNotEmpty ? lines.first.descripcion.trim() : '';
  final showConcepto = concepto.isNotEmpty && concepto != firstLine;
  return '''
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8"/>
<title>${_esc(title)} ${_esc(factura.refLabel)}</title>
<style>
  @page { size: A4; margin: 14mm; }
  * { box-sizing: border-box; }
  body {
    font-family: "Plus Jakarta Sans", "Segoe UI", Helvetica, Arial, sans-serif;
    color: #161412;
    margin: 0;
    background: #fff;
  }
  .sheet { max-width: 182mm; margin: 0 auto; }
  .toolbar { display: flex; justify-content: flex-end; margin-bottom: 12px; }
  .toolbar button {
    font: inherit; background: #1B5F59; color: #F7FFFE; border: 0;
    border-radius: 8px; padding: 8px 14px; cursor: pointer;
  }
  .mast {
    display: flex; justify-content: space-between; align-items: flex-end;
    gap: 24px; padding-bottom: 10px; border-bottom: 2px solid #1B5F59;
  }
  .brand { font-size: 24px; font-weight: 700; color: #1B5F59; letter-spacing: -0.02em; }
  .doc { text-align: right; }
  .kind { font-size: 14px; font-weight: 600; color: #1B5F59; margin: 0 0 4px; }
  .no { font-size: 36px; font-weight: 700; letter-spacing: -0.03em; line-height: 1; }
  .parties { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin: 18px 0 8px; }
  .party { padding: 18px 20px; min-height: 124px; font-size: 13px; line-height: 1.45; }
  .party.emisor { background: #F3EEE6; }
  .party.dest { background: #D7EBE8; }
  .party h2 {
    font-size: 15px; font-weight: 700; margin: 0 0 10px;
  }
  .name { font-weight: 700; font-size: 15px; margin-bottom: 4px; }
  .ids { margin-top: 8px; color: #3F4A48; font-size: 12px; }
  .meta {
    display: grid; grid-template-columns: 1fr 1fr; column-gap: 36px;
    margin: 8px 0 20px;
  }
  .meta-row {
    display: grid; grid-template-columns: 128px 1fr; gap: 8px;
    padding: 8px 0; border-bottom: 1px solid #DFD8CC; font-size: 13px;
  }
  .meta-row .lab { color: #1B5F59; font-weight: 600; }
  table.lines { width: 100%; border-collapse: collapse; }
  table.lines th {
    background: #1B5F59; color: #F7FFFE; font-size: 11px; font-weight: 600;
    letter-spacing: 0.06em; text-transform: uppercase; padding: 10px 8px;
    text-align: left;
  }
  table.lines td { padding: 10px 8px; border-bottom: 1px solid #EDE8DF; font-size: 13px; }
  table.lines th.num, table.lines td.num { text-align: right; white-space: nowrap; }
  .note {
    background: #FFF4C2; border-left: 3px solid #B45309;
    padding: 10px 12px; margin: 14px 0 0; font-size: 12.5px; line-height: 1.4;
  }
  .sum { width: 300px; margin: 18px 0 0 auto; }
  .sum-row {
    display: flex; justify-content: space-between; gap: 16px;
    padding: 6px 14px; font-size: 13px;
  }
  .sum-total {
    display: flex; justify-content: space-between; align-items: center;
    gap: 16px; margin-top: 4px; background: #1B5F59; color: #F7FFFE;
    padding: 12px 14px; font-weight: 700; font-size: 16px;
  }
  .foot {
    display: flex; justify-content: space-between; align-items: flex-end;
    gap: 24px; margin-top: 28px;
  }
  .muted { color: #6B645C; font-size: 11.5px; line-height: 1.45; max-width: 360px; }
  .qr { width: 112px; height: 112px; }
  .fine {
    text-align: center; color: #6B645C; font-size: 11px; margin-top: 28px;
  }
  @media print {
    .toolbar { display: none !important; }
    .sheet { max-width: none; }
  }
</style>
</head>
<body>
<div class="sheet">
  <div class="toolbar"><button type="button" onclick="window.print()">Imprimir</button></div>
  <div class="mast">
    <div class="brand">${_esc(emisorNombre.isEmpty ? 'Emisor' : emisorNombre)}</div>
    <div class="doc">
      <div class="kind">$title</div>
      <div class="no">${_esc(factura.refLabel)}</div>
    </div>
  </div>
  <div class="parties">
    <div class="party emisor">
      <h2>Emisor</h2>
      <div class="name">${_esc(emisorNombre)}</div>
      ${emisorNif.isEmpty ? '' : '<div class="ids">NIF ${_esc(emisorNif)}</div>'}
    </div>
    $dest
  </div>
  <div class="meta">
    <div>
      ${_meta('Fecha', fecha)}
      ${_meta('Vencimiento', venc)}
      ${_meta('Forma de pago', pago)}
    </div>
    <div>
      ${_meta('Nº', factura.refLabel)}
      ${_meta('Tipo', tipo)}
      ${_meta('Moneda', 'EUR')}
    </div>
  </div>
  <table class="lines">
    <thead>
      <tr>
        <th>Descripción</th>
        <th class="num">Cant.</th>
        <th class="num">Precio</th>
        <th class="num">IVA</th>
        <th class="num">Base</th>
        <th class="num">Importe</th>
      </tr>
    </thead>
    <tbody>$lineRows</tbody>
  </table>
  ${showConcepto ? '<div class="note">${_esc(concepto)}</div>' : ''}
  ${notas.isEmpty ? '' : '<div class="note">${_esc(notas)}</div>'}
  <div class="sum">
    $taxRows
    <div class="sum-total">
      <span>Total</span>
      <span>${_esc(formatCents(total))} €</span>
    </div>
  </div>
  <div class="foot">
    <div class="muted">Factura verificable en la sede electrónica de la AEAT.</div>
    $qrImg
  </div>
  <div class="fine">${_esc(emisorNombre)}${emisorNif.isEmpty ? '' : ' · NIF ${_esc(emisorNif)}'}</div>
</div>
<script>
window.addEventListener('load', function () {
  setTimeout(function () { window.print(); }, 280);
});
</script>
</body>
</html>
''';
}

String _meta(String label, String value) {
  return '<div class="meta-row"><span class="lab">${_esc(label)}</span><span>${_esc(value)}</span></div>';
}

String _pagoEs(String key) {
  return switch (key) {
    'transferencia' => 'Transferencia',
    'efectivo' => 'Efectivo',
    'tarjeta' => 'Tarjeta',
    'domiciliacion' => 'Domiciliación',
    'otro' => 'Otro',
    _ => key,
  };
}

String _esc(String raw) {
  return raw
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
