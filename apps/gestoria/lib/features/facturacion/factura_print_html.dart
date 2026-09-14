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
  return '''
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8"/>
<title>${_esc(title)} ${_esc(factura.refLabel)}</title>
<style>
  body { font-family: Georgia, "Times New Roman", serif; color: #161412; margin: 24px; }
  h1 { font-size: 22px; letter-spacing: 0.08em; margin: 0 0 16px; }
  .grid { display: flex; gap: 32px; justify-content: space-between; margin-bottom: 24px; }
  .muted { color: #6B645C; font-size: 13px; }
  table { width: 100%; border-collapse: collapse; margin: 16px 0; }
  th, td { text-align: left; padding: 8px 6px; border-bottom: 1px solid #DFD8CC; font-size: 14px; }
  th { font-size: 12px; letter-spacing: 0.04em; color: #6B645C; }
  .num { text-align: right; }
  .tot { width: 280px; margin-left: auto; }
  .qr { width: 140px; height: 140px; }
  .foot { display: flex; justify-content: space-between; align-items: flex-end; margin-top: 28px; gap: 24px; }
  @media print { body { margin: 12mm; } }
</style>
</head>
<body>
<h1>$title</h1>
<div class="grid">
  <div>
    <div class="muted">Emisor</div>
    <div><strong>${_esc(emisorNombre)}</strong></div>
    <div>NIF ${_esc(emisorNif)}</div>
  </div>
  <div>
    <div><strong>Nº ${_esc(factura.refLabel)}</strong></div>
    <div>Fecha ${_esc(toDmyDate(factura.fecha) ?? factura.fecha ?? '')}</div>
    ${factura.vencimiento == null ? '' : '<div>Vencimiento ${_esc(toDmyDate(factura.vencimiento) ?? factura.vencimiento!)}</div>'}
    <div class="muted">${_esc(factura.tipoFactura)}</div>
  </div>
</div>
${factura.hasDestinatario || (factura.destinatarioNombre ?? '').isNotEmpty ? '''
<div class="muted">Destinatario</div>
<div><strong>${_esc(factura.destinatarioNombre ?? '')}</strong></div>
${factura.destinatarioNif == null ? '' : '<div>NIF ${_esc(factura.destinatarioNif!)}</div>'}
${factura.destinatarioDireccion == null ? '' : '<div>${_esc(factura.destinatarioDireccion!)}</div>'}
${factura.destinatarioEmail == null ? '' : '<div>${_esc(factura.destinatarioEmail!)}</div>'}
''' : ''}
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
