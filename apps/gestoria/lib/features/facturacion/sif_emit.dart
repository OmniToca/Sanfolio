import 'package:gestoria_auth/gestoria_auth.dart';

/// Flutter jen klikne Emitir. Klíč a AEAT zůstávají v Edge.
Future<SifEmitResult> emitFacturaViaSif({
  required String tenantId,
  required String facturaId,
}) async {
  final client = trySupabaseClient();
  if (client == null) {
    return const SifEmitResult(ok: false, error: 'not_configured');
  }
  final response = await client.functions.invoke(
    'sif-emit',
    body: {
      'tenant_id': tenantId,
      'factura_id': facturaId,
    },
  );
  final data = response.data;
  if (data is! Map) {
    return SifEmitResult(ok: false, error: response.status.toString());
  }
  final error = '${data['error'] ?? ''}'.trim();
  return SifEmitResult(
    ok: data['ok'] == true,
    error: error.isEmpty ? null : error,
    sifStatus: '${data['sif_status'] ?? ''}'.trim().isEmpty
        ? null
        : '${data['sif_status']}',
    sifExternalId: '${data['sif_external_id'] ?? ''}'.trim().isEmpty
        ? null
        : '${data['sif_external_id']}',
  );
}

class SifEmitResult {
  const SifEmitResult({
    required this.ok,
    this.error,
    this.sifStatus,
    this.sifExternalId,
  });

  final bool ok;
  final String? error;
  final String? sifStatus;
  final String? sifExternalId;
}
