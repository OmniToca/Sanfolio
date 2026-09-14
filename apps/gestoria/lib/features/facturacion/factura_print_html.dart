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
          '<td class="num">${_esc(formatCents(line.precioUnitarioCents))} €</td>'
          '<td class="num">${_esc(ivaRateLabel(line.ivaBps))}</td>'
          '<td class="num">${_esc(formatCents(line.totalCents))} €</td>'
          '</tr>',
  ].join();
  final taxRows = [
    for (final row in byRate)
      '<tr>'
          '<td>Base ${_esc(ivaRateLabel(row.ivaBps))}</td>'
          '<td class="num">${_esc(formatCents(row.baseCents))} €</td>'
          '</tr>'
          '<tr>'
          '<td>IVA ${_esc(ivaRateLabel(row.ivaBps))}</td>'
          '<td class="num">${_esc(formatCents(row.ivaCents))} €</td>'
          '</tr>',
  ].join();
  final destBlock = factura.hasDestinatario ||
          (factura.destinatarioNombre ?? '').isNotEmpty
      ? '''
<div class="box">
  <div class="k">Destinatario</div>
  <div class="name">${_esc(factura.destinatarioNombre ?? '')}</div>
  ${factura.destinatarioNif == null ? '' : '<div>NIF ${_esc(factura.destinatarioNif!)}</div>'}
  ${factura.destinatarioDireccion == null ? '' : '<div>${_esc(factura.destinatarioDireccion!)}</div>'}
  ${factura.destinatarioEmail == null ? '' : '<div>${_esc(factura.destinatarioEmail!)}</div>'}
</div>'''
      : '<div class="box"><div class="k">Destinatario</div><div>—</div></div>';
  return '''
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8"/>
<title>${_esc(title)} ${_esc(factura.refLabel)}</title>
<style>
  @page { size: A4; margin: 12mm; }
  * { box-sizing: border-box; }
  body { font-family: "Plus Jakarta Sans", "Segoe UI", Helvetica, Arial, sans-serif; color: #161412; margin: 0; background: #fff; }
  .sheet { max-width: 210mm; margin: 0 auto; padding: 8mm 10mm 12mm; }
  .bar { height: 6px; background: #1B5F59; margin: 0 -10mm 16px; }
  .head { display: flex; justify-content: space-between; align-items: flex-start; gap: 24px; margin-bottom: 18px; }
  h1 { font-family: Georgia, "Times New Roman", serif; font-size: 22px; letter-spacing: 0.06em; margin: 0 0 6px; }
  .meta { text-align: right; font-size: 13px; line-height: 1.45; }
  .meta strong { font-size: 16px; }
  .grid { display: flex; gap: 16px; margin-bottom: 18px; }
  .box { flex: 1; border: 1px solid #DFD8CC; border-radius: 10px; padding: 12px 14px; background: #FFFCF8; }
  .k { color: #6B645C; font-size: 11px; letter-spacing: 0.08em; text-transform: uppercase; margin-bottom: 6px; }
  .name { font-weight: 600; font-size: 15px; margin-bottom: 2px; }
  table { width: 100%; border-collapse: collapse; margin: 8px 0 16px; }
  th, td { text-align: left; padding: 9px 8px; border-bottom: 1px solid #DFD8CC; font-size: 13px; }
  thead th { background: #EDE8DF; font-size: 11px; letter-spacing: 0.04em; color: #6B645C; text-transform: uppercase; }
  .num { text-align: right; white-space: nowrap; }
  .tot { width: 280px; margin-left: auto; }
  .tot td { border-bottom: 0; padding: 5px 8px; }
  .tot tr:last-child td { border-top: 1px solid #161412; font-size: 15px; }
  .qr { width: 120px; height: 120px; }
  .foot { display: flex; justify-content: space-between; align-items: flex-end; margin-top: 24px; gap: 24px; }
  .muted { color: #6B645C; font-size: 12px; line-height: 1.4; }
  .toolbar { display: flex; justify-content: flex-end; gap: 8px; margin-bottom: 12px; }
  .toolbar button { font: inherit; background: #1B5F59; color: #F7FFFE; border: 0; border-radius: 8px; padding: 8px 14px; cursor: pointer; }
  @media print {
    .toolbar { display: none !important; }
    body { background: #fff; }
    .sheet { padding: 0; max-width: none; }
    .bar { margin: 0 0 12px; }
  }
</style>
</head>
<body>
<div class="sheet">
  <div class="toolbar"><button type="button" onclick="window.print()">Imprimir</button></div>
  <div class="bar"></div>
  <div class="head">
    <div>
      <h1>$title</h1>
      <div class="muted">${_esc(factura.tipoFactura)}</div>
    </div>
    <div class="meta">
      <div><strong>Nº ${_esc(factura.refLabel)}</strong></div>
      <div>Fecha ${_esc(toDmyDate(factura.fecha) ?? factura.fecha ?? '')}</div>
      ${factura.vencimiento == null ? '' : '<div>Vencimiento ${_esc(toDmyDate(factura.vencimiento) ?? factura.vencimiento!)}</div>'}
    </div>
  </div>
  <div class="grid">
    <div class="box">
      <div class="k">Emisor</div>
      <div class="name">${_esc(emisorNombre)}</div>
      <div>NIF ${_esc(emisorNif)}</div>
    </div>
    $destBlock
  </div>
  <table>
    <thead>
      <tr>
        <th>Descripción</th>
        <th class="num">Cant.</th>
        <th class="num">Precio</th>
        <th class="num">IVA</th>
        <th class="num">Importe</th>
      </tr>
    </thead>
    <tbody>$lineRows</tbody>
  </table>
  <table class="tot">
    <tbody>
      $taxRows
      <tr>
        <td><strong>Total</strong></td>
        <td class="num"><strong>${_esc(formatCents(total))} €</strong></td>
      </tr>
    </tbody>
  </table>
  ${(factura.concepto ?? '').trim().isEmpty ? '' : '<p>${_esc(factura.concepto!)}</p>'}
  ${(factura.notas ?? '').trim().isEmpty ? '' : '<p class="muted">${_esc(factura.notas!)}</p>'}
  ${factura.formaPago == null ? '' : '<p>Forma de pago: ${_esc(_pagoEs(factura.formaPago!))}</p>'}
  <div class="foot">
    <div class="muted">Factura verificable en la sede electrónica de la AEAT.</div>
    $qrImg
  </div>
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
