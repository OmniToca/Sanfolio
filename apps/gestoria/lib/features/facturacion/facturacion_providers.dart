import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/documents/documento_storage.dart';
import '../../core/time/office_date.dart';
import '../ai/ai_providers.dart';
import 'factura.dart';

const _facturaSelect =
    'id, cliente_id, documento_id, direccion, estado, proveedor_nombre, '
    'proveedor_nif, destinatario_nombre, destinatario_nif, destinatario_direccion, '
    'destinatario_email, serie, numero, fecha, vencimiento, concepto, notas, '
    'forma_pago, tipo_factura, lineas, base_cents, iva_cents, iva_bps, total_cents, '
    'sif_provider, sif_external_id, sif_status, sif_qr_url, sif_aeat_url, sif_error, '
    'sif_fecha_expedicion, '
    'clientes ( nombre )';

/// Kniha kanceláře. Filtr směru na obrazovce.
final facturasOfficeProvider =
    FutureProvider.family<List<Factura>, String>((ref, direccion) async {
  ref.watch(authControllerProvider);
  final auth = await ref.watch(authControllerProvider.future);
  final tenantId = auth.currentTenantId;
  final client = trySupabaseClient();
  if (tenantId == null || client == null) return const [];
  final rows = await client
      .from('facturas')
      .select(_facturaSelect)
      .eq('tenant_id', tenantId)
      .eq('direccion', direccion)
      .isFilter('deleted_at', null)
      .order('fecha', ascending: false);
  return _parse(rows);
});

final facturasClienteProvider =
    FutureProvider.family<List<Factura>, String>((ref, clienteId) async {
  ref.watch(authControllerProvider);
  final auth = await ref.watch(authControllerProvider.future);
  final tenantId = auth.currentTenantId;
  final client = trySupabaseClient();
  if (tenantId == null || client == null) return const [];
  final rows = await client
      .from('facturas')
      .select(_facturaSelect)
      .eq('tenant_id', tenantId)
      .eq('cliente_id', clienteId)
      .eq('direccion', 'recibida')
      .isFilter('deleted_at', null)
      .order('fecha', ascending: false);
  return _parse(rows);
});

final facturaByIdProvider =
    FutureProvider.family<Factura?, String>((ref, facturaId) async {
  ref.watch(authControllerProvider);
  final auth = await ref.watch(authControllerProvider.future);
  final tenantId = auth.currentTenantId;
  final client = trySupabaseClient();
  if (tenantId == null || client == null) return null;
  final row = await client
      .from('facturas')
      .select(_facturaSelect)
      .eq('tenant_id', tenantId)
      .eq('id', facturaId)
      .isFilter('deleted_at', null)
      .maybeSingle();
  if (row == null) return null;
  return Factura.fromRow(Map<dynamic, dynamic>.from(row));
});

List<Factura> _parse(Object rows) {
  final out = <Factura>[];
  if (rows is! List) return out;
  for (final raw in rows) {
    if (raw is Map) out.add(Factura.fromRow(raw));
  }
  return out;
}

/// Gestor ukládá přijatou. AI sem nesmí.
Future<void> guardarFacturaRecibida({
  required String documentoId,
  required Map<String, String> fields,
  String? docTipo,
}) async {
  if (docTipo != 'factura_recibida') return;
  final draft = recibidaFromExtract(fields);
  final client = trySupabaseClient();
  if (client == null) return;
  await client.rpc(
    'guardar_factura_recibida',
    params: {
      'p_documento_id': documentoId,
      'p_proveedor_nombre': draft.proveedorNombre,
      'p_proveedor_nif': draft.proveedorNif,
      'p_numero': draft.numero,
      'p_fecha': _isoDate(draft.fecha),
      'p_vencimiento': _isoDate(draft.vencimiento),
      'p_base_cents': draft.baseCents,
      'p_iva_cents': draft.ivaCents,
      'p_iva_bps': draft.ivaBps,
      'p_total_cents': draft.totalCents,
      'p_concepto': draft.concepto,
    },
  );
}

Future<int> nextFacturaNumero({
  required String tenantId,
  String? serie,
}) async {
  final client = trySupabaseClient();
  if (client == null) return 1;
  final n = await client.rpc(
    'next_factura_numero',
    params: {
      'p_tenant_id': tenantId,
      'p_serie': serie,
    },
  );
  if (n is int) return n;
  return int.tryParse('$n') ?? 1;
}

Future<String> createFacturaEmitida({
  required String tenantId,
  required String? clienteId,
  required String? destinatarioNombre,
  required String? destinatarioNif,
  String? destinatarioDireccion,
  String? destinatarioEmail,
  required String serie,
  required String numero,
  required String fecha,
  String? vencimiento,
  required String concepto,
  String? notas,
  String? formaPago,
  String tipoFactura = 'F1',
  List<Map<String, Object?>> lineas = const [],
  required int baseCents,
  required int ivaCents,
  required int totalCents,
  int? ivaBps,
  String? createdBy,
}) async {
  final client = trySupabaseClient();
  if (client == null) throw StateError('not configured');
  final inserted = await client
      .from('facturas')
      .insert({
        'tenant_id': tenantId,
        'cliente_id': clienteId,
        'direccion': 'emitida',
        'estado': 'borrador',
        'destinatario_nombre': destinatarioNombre,
        'destinatario_nif': destinatarioNif,
        'destinatario_direccion': destinatarioDireccion,
        'destinatario_email': destinatarioEmail,
        'serie': serie,
        'numero': numero,
        'fecha': fecha,
        'vencimiento': vencimiento,
        'concepto': concepto,
        'notas': notas,
        'forma_pago': formaPago,
        'tipo_factura': tipoFactura,
        'lineas': lineas,
        'base_cents': baseCents,
        'iva_cents': ivaCents,
        'iva_bps': ivaBps ?? 2100,
        'total_cents': totalCents,
        'created_by': ?createdBy,
      })
      .select('id')
      .single();
  return '${inserted['id']}';
}

Future<void> hideFactura(String facturaId) async {
  final client = trySupabaseClient();
  if (client == null) return;
  await client.from('facturas').update({
    'deleted_at': DateTime.now().toUtc().toIso8601String(),
  }).eq('id', facturaId);
}

/// PDF/fotka přijaté. Extract běží na pozadí; Guardar je na kartě.
Future<void> attachFacturaRecibida({
  required String tenantId,
  required String clienteId,
  required Uint8List bytes,
  required String originalName,
  String? createdBy,
}) async {
  final path = documentoStoragePath(
    tenantId: tenantId,
    clienteId: clienteId,
    originalName: originalName,
  );
  await uploadDocumentoBytes(
    path: path,
    bytes: bytes,
    originalName: originalName,
  );
  await insertDocumentoRow(
    tenantId: tenantId,
    clienteId: clienteId,
    tipo: 'factura_recibida',
    storagePath: path,
    originalName: originalName,
    createdBy: createdBy,
  );
  startExtractInBackground(
    tenantId: tenantId,
    clienteId: clienteId,
    storagePath: path,
    mime: mimeForOfficeFile(originalName),
    docTipo: 'factura_recibida',
    bloqueKey: 'factura_recibida',
  );
}

String? _isoDate(String? raw) => toIsoDate(raw);
