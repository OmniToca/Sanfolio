import '../../core/money/cents.dart';

/// Řádek knihy. Peníze jen integer cents.
class Factura {
  const Factura({
    required this.id,
    required this.direccion,
    required this.estado,
    this.clienteId,
    this.documentoId,
    this.clienteNombre,
    this.proveedorNombre,
    this.proveedorNif,
    this.destinatarioNombre,
    this.destinatarioNif,
    this.serie,
    this.numero,
    this.fecha,
    this.vencimiento,
    this.concepto,
    this.baseCents = 0,
    this.ivaCents = 0,
    this.ivaBps,
    this.totalCents = 0,
    this.sifProvider,
    this.sifExternalId,
    this.sifStatus,
    this.sifQrUrl,
    this.sifError,
  });

  final String id;
  final String direccion;
  final String estado;
  final String? clienteId;
  final String? documentoId;
  final String? clienteNombre;
  final String? proveedorNombre;
  final String? proveedorNif;
  final String? destinatarioNombre;
  final String? destinatarioNif;
  final String? serie;
  final String? numero;
  final String? fecha;
  final String? vencimiento;
  final String? concepto;
  final int baseCents;
  final int ivaCents;
  final int? ivaBps;
  final int totalCents;
  final String? sifProvider;
  final String? sifExternalId;
  final String? sifStatus;
  final String? sifQrUrl;
  final String? sifError;

  bool get isRecibida => direccion == 'recibida';
  bool get isEmitida => direccion == 'emitida';
  bool get canEmitir =>
      isEmitida && (estado == 'borrador' || estado == 'guardada' || estado == 'error');
  bool get alreadyEmitted => isEmitida && estado == 'emitida';

  String get counterparty {
    if (isRecibida) {
      return (proveedorNombre ?? '').trim().isNotEmpty
          ? proveedorNombre!.trim()
          : (proveedorNif ?? '').trim();
    }
    return (destinatarioNombre ?? clienteNombre ?? '').trim();
  }

  factory Factura.fromRow(Map<dynamic, dynamic> raw) {
    final clientes = raw['clientes'];
    String? clienteNombre;
    if (clientes is Map) {
      clienteNombre = '${clientes['nombre'] ?? ''}'.trim();
      if (clienteNombre.isEmpty) clienteNombre = null;
    }
    return Factura(
      id: '${raw['id']}',
      direccion: '${raw['direccion'] ?? ''}',
      estado: '${raw['estado'] ?? ''}',
      clienteId: _opt(raw['cliente_id']),
      documentoId: _opt(raw['documento_id']),
      clienteNombre: clienteNombre,
      proveedorNombre: _opt(raw['proveedor_nombre']),
      proveedorNif: _opt(raw['proveedor_nif']),
      destinatarioNombre: _opt(raw['destinatario_nombre']),
      destinatarioNif: _opt(raw['destinatario_nif']),
      serie: _opt(raw['serie']),
      numero: _opt(raw['numero']),
      fecha: _opt(raw['fecha']),
      vencimiento: _opt(raw['vencimiento']),
      concepto: _opt(raw['concepto']),
      baseCents: _cents(raw['base_cents']),
      ivaCents: _cents(raw['iva_cents']),
      ivaBps: _intOrNull(raw['iva_bps']),
      totalCents: _cents(raw['total_cents']),
      sifProvider: _opt(raw['sif_provider']),
      sifExternalId: _opt(raw['sif_external_id']),
      sifStatus: _opt(raw['sif_status']),
      sifQrUrl: _opt(raw['sif_qr_url']),
      sifError: _opt(raw['sif_error']),
    );
  }
}

/// Návrh přijaté z extractu. Guardar zapíše cents, AI ne.
class RecibidaDraft {
  const RecibidaDraft({
    this.proveedorNombre,
    this.proveedorNif,
    this.numero,
    this.fecha,
    this.vencimiento,
    this.concepto,
    this.baseCents = 0,
    this.ivaCents = 0,
    this.ivaBps,
    this.totalCents = 0,
  });

  final String? proveedorNombre;
  final String? proveedorNif;
  final String? numero;
  final String? fecha;
  final String? vencimiento;
  final String? concepto;
  final int baseCents;
  final int ivaCents;
  final int? ivaBps;
  final int totalCents;

  bool get isEmpty =>
      (proveedorNombre ?? '').trim().isEmpty &&
      (proveedorNif ?? '').trim().isEmpty &&
      (numero ?? '').trim().isEmpty &&
      totalCents == 0 &&
      baseCents == 0;
}

/// Mapuje pole dokladu na knihu. Částky jdou přes [parseEurosToCents].
RecibidaDraft recibidaFromExtract(Map<String, String> fields) {
  final total = parseEurosToCents(fields['fields.amount'] ?? '') ?? 0;
  var base = parseEurosToCents(fields['fields.base'] ?? '') ?? 0;
  var iva = parseEurosToCents(fields['fields.iva'] ?? '') ?? 0;
  if (base == 0 && total > 0 && iva > 0 && iva < total) {
    base = total - iva;
  }
  if (iva == 0 && total > 0 && base > 0 && base < total) {
    iva = total - base;
  }
  if (base == 0 && iva == 0 && total > 0) {
    base = total;
  }
  return RecibidaDraft(
    proveedorNombre: _first(fields, const ['fields.company', 'fields.nombre']),
    proveedorNif: _first(fields, const ['fields.supplierNif']),
    numero: _first(fields, const ['fields.invoiceNo', 'fields.docNumber']),
    fecha: _first(fields, const ['fields.issued', 'fields.date']),
    vencimiento: _first(fields, const ['fields.due']),
    concepto: _first(fields, const ['fields.concept']),
    baseCents: base,
    ivaCents: iva,
    ivaBps: ivaBpsFromRate(fields['fields.ivaRate']),
    totalCents: total,
  );
}

int? ivaBpsFromRate(String? raw) {
  final t = (raw ?? '').trim().replaceAll('%', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  final n = double.tryParse(t);
  if (n == null) return null;
  if (n > 0 && n <= 1) return (n * 10000).round();
  if (n > 1 && n <= 100) return (n * 100).round();
  return n.round();
}

String receivedInvoicesCsv(List<Factura> rows) {
  final buf = StringBuffer(
    'fecha;proveedor;nif;numero;base;iva;total;cliente;concepto\n',
  );
  for (final r in rows.where((x) => x.isRecibida)) {
    buf.writeln(
      [
        r.fecha ?? '',
        _csv(r.proveedorNombre),
        r.proveedorNif ?? '',
        r.numero ?? '',
        formatCents(r.baseCents),
        formatCents(r.ivaCents),
        formatCents(r.totalCents),
        _csv(r.clienteNombre),
        _csv(r.concepto),
      ].join(';'),
    );
  }
  return buf.toString();
}

String? _opt(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

int _cents(Object? v) {
  if (v is int) return v;
  return int.tryParse('$v') ?? 0;
}

int? _intOrNull(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse('$v');
}

String? _first(Map<String, String> fields, List<String> keys) {
  for (final k in keys) {
    final v = (fields[k] ?? '').trim();
    if (v.isNotEmpty) return v;
  }
  return null;
}

String _csv(String? raw) {
  final v = (raw ?? '').replaceAll(';', ',');
  if (v.contains('"') || v.contains('\n')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}
