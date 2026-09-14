import 'package:gestoria_auth/gestoria_auth.dart';

/// Flutter jen klikne Emitir / Ověřit. Klíč a AEAT zůstávají v Edge.
Future<SifCallResult> emitFacturaViaSif({
  required String tenantId,
  required String facturaId,
}) {
  return _invokeSif(
    'sif-emit',
    tenantId: tenantId,
    facturaId: facturaId,
  );
}

Future<SifCallResult> verifyFacturaViaSif({
  required String tenantId,
  required String facturaId,
}) {
  return _invokeSif(
    'sif-status',
    tenantId: tenantId,
    facturaId: facturaId,
  );
}

Future<SifCallResult> _invokeSif(
  String fn, {
  required String tenantId,
  required String facturaId,
}) async {
  final client = trySupabaseClient();
  if (client == null) {
    return const SifCallResult(ok: false, error: 'not_configured');
  }
  final response = await client.functions.invoke(
    fn,
    body: {
      'tenant_id': tenantId,
      'factura_id': facturaId,
    },
  );
  final data = response.data;
  if (data is! Map) {
    return SifCallResult(ok: false, error: response.status.toString());
  }
  final error = '${data['error'] ?? ''}'.trim();
  return SifCallResult(
    ok: data['ok'] == true,
    error: error.isEmpty ? null : error,
    sifStatus: _opt(data['sif_status']),
    sifExternalId: _opt(data['sif_external_id']),
    bookEstado: _opt(data['book_estado']),
    sifQrUrl: _opt(data['sif_qr_url']),
    sifAeatUrl: _opt(data['sif_aeat_url']),
  );
}

String? _opt(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

class SifCallResult {
  const SifCallResult({
    required this.ok,
    this.error,
    this.sifStatus,
    this.sifExternalId,
    this.bookEstado,
    this.sifQrUrl,
    this.sifAeatUrl,
  });

  final bool ok;
  final String? error;
  final String? sifStatus;
  final String? sifExternalId;
  final String? bookEstado;
  final String? sifQrUrl;
  final String? sifAeatUrl;
}

/// i18n klíč snackbaru. Neznámý error padá na emit/verify Error.
String sifSnackKey(SifCallResult result, {required bool verify}) {
  if (result.ok) {
    if (result.bookEstado == 'pendiente') {
      return verify ? 'facturacion.verifyPending' : 'facturacion.emitPending';
    }
    if (result.bookEstado == 'error') {
      return verify ? 'facturacion.verifyRejected' : 'facturacion.emitError';
    }
    return verify ? 'facturacion.verifyOk' : 'facturacion.emitOk';
  }
  switch (result.error) {
    case 'sif_not_configured':
      return 'facturacion.sifNotConfigured';
    case 'emisor_nif_required':
      return 'facturacion.emisorNifRequired';
    case 'destinatario_required':
      return 'facturacion.destinatarioRequired';
    case 'not_submitted':
      return 'facturacion.notSubmitted';
    case 'sif_in_flight':
      return 'facturacion.sifInFlight';
    default:
      return verify ? 'facturacion.verifyError' : 'facturacion.emitError';
  }
}
