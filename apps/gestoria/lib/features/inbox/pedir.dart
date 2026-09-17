import 'package:gestoria_auth/gestoria_auth.dart';

import '../mensajes/mensaje_templates.dart';

/// Jedna výzva k nachystání. Odesílá gestor, ne tahle struktura.
class PedirDraftRequest {
  const PedirDraftRequest({
    required this.clienteId,
    required this.clienteNombre,
    required this.templateKey,
    required this.bloqueKey,
    this.bloqueId,
    this.lastRequestedAt,
    this.hasEmail = true,
    this.hasTel = true,
    this.fecha = '—',
    this.inmueble = '—',
    this.documento = '—',
  });

  final String clienteId;
  final String clienteNombre;
  final String templateKey;
  final String bloqueKey;
  final String? bloqueId;
  final DateTime? lastRequestedAt;
  final bool hasEmail;
  final bool hasTel;
  final String fecha;
  final String inmueble;
  final String documento;

  bool get hasChannel => hasEmail || hasTel;
}

enum PedirSkipReason { noChannel, askedRecently }

/// Čistá pravidla výzvy — cron, inbox i kampaň.
bool canPedirAlCliente({
  required DateTime? lastRequestedAt,
  required int nudgeIntervalDays,
  DateTime? now,
}) {
  if (lastRequestedAt == null) return true;
  final days = nudgeIntervalDays < 0 ? 0 : nudgeIntervalDays;
  final n = (now ?? DateTime.now()).toUtc();
  final next = lastRequestedAt.toUtc().add(Duration(days: days));
  return !n.isBefore(next);
}

PedirSkipReason? pedirSkipReason(
  PedirDraftRequest request, {
  required int nudgeIntervalDays,
  DateTime? now,
}) {
  if (!request.hasChannel) return PedirSkipReason.noChannel;
  if (!canPedirAlCliente(
    lastRequestedAt: request.lastRequestedAt,
    nudgeIntervalDays: nudgeIntervalDays,
    now: now,
  )) {
    return PedirSkipReason.askedRecently;
  }
  return null;
}

class PedirBatchPlan {
  const PedirBatchPlan({
    required this.toDraft,
    required this.noChannel,
    required this.askedRecently,
  });

  final List<PedirDraftRequest> toDraft;
  final int noChannel;
  final int askedRecently;
}

PedirBatchPlan planPedirDrafts(
  Iterable<PedirDraftRequest> requests, {
  required int nudgeIntervalDays,
  DateTime? now,
}) {
  final toDraft = <PedirDraftRequest>[];
  var noChannel = 0;
  var askedRecently = 0;
  for (final request in requests) {
    switch (pedirSkipReason(
      request,
      nudgeIntervalDays: nudgeIntervalDays,
      now: now,
    )) {
      case PedirSkipReason.noChannel:
        noChannel++;
      case PedirSkipReason.askedRecently:
        askedRecently++;
      case null:
        toDraft.add(request);
    }
  }
  return PedirBatchPlan(
    toDraft: toDraft,
    noChannel: noChannel,
    askedRecently: askedRecently,
  );
}

class PedirBatchResult {
  const PedirBatchResult({
    required this.drafted,
    required this.noChannel,
    required this.askedRecently,
    this.errors = 0,
  });

  final int drafted;
  final int noChannel;
  final int askedRecently;
  final int errors;
}

/// Drafty + razítko. Status `sent` sem nepatří.
Future<PedirBatchResult> writePedirDrafts({
  required String tenantId,
  required List<PedirDraftRequest> requests,
  required String despacho,
  required int nudgeIntervalDays,
  DateTime? now,
}) async {
  final plan = planPedirDrafts(
    requests,
    nudgeIntervalDays: nudgeIntervalDays,
    now: now,
  );
  if (plan.toDraft.isEmpty) {
    return PedirBatchResult(
      drafted: 0,
      noChannel: plan.noChannel,
      askedRecently: plan.askedRecently,
    );
  }
  final client = trySupabaseClient();
  if (client == null) {
    return PedirBatchResult(
      drafted: 0,
      noChannel: plan.noChannel,
      askedRecently: plan.askedRecently,
      errors: plan.toDraft.length,
    );
  }
  final uid = client.auth.currentUser?.id;
  final office = despacho.trim().isEmpty ? '—' : despacho.trim();
  try {
    await client.from('mensajes').insert([
      for (final request in plan.toDraft)
        _draftRow(
          tenantId: tenantId,
          uid: uid,
          request: request,
          despacho: office,
        ),
    ]);
  } on Object {
    return PedirBatchResult(
      drafted: 0,
      noChannel: plan.noChannel,
      askedRecently: plan.askedRecently,
      errors: plan.toDraft.length,
    );
  }
  final bloqueIds = [
    for (final request in plan.toDraft)
      if ((request.bloqueId ?? '').isNotEmpty) request.bloqueId!,
  ];
  if (bloqueIds.isNotEmpty) {
    try {
      await client.from('bloques').update({
        'last_requested_at': DateTime.now().toUtc().toIso8601String(),
      }).inFilter('id', bloqueIds).eq('tenant_id', tenantId);
    } on Object {
      // Draft už je. Další Pedir může znovu projít, dokud razítko nesedí.
    }
  }
  return PedirBatchResult(
    drafted: plan.toDraft.length,
    noChannel: plan.noChannel,
    askedRecently: plan.askedRecently,
  );
}

Map<String, dynamic> _draftRow({
  required String tenantId,
  required String? uid,
  required PedirDraftRequest request,
  required String despacho,
}) {
  final filled = filledTemplate(
    key: request.templateKey,
    vars: {
      'nombre': request.clienteNombre,
      'bloque': request.bloqueKey,
      'documento': request.documento,
      'fecha': request.fecha.trim().isEmpty ? '—' : request.fecha,
      'despacho': despacho,
      'inmueble': request.inmueble.trim().isEmpty ? '—' : request.inmueble,
      'campos_faltantes': '—',
    },
  );
  return {
    'tenant_id': tenantId,
    'cliente_id': request.clienteId,
    'canal': request.hasEmail ? 'email' : 'whatsapp',
    'asunto': filled.asunto,
    'cuerpo': filled.cuerpo,
    'locale_original': 'es',
    'translations': {'es': filled.cuerpo},
    'status': 'draft',
    'template_key': request.templateKey,
    'bloque_id': request.bloqueId,
    'sent_at': null,
    'created_by': uid,
  };
}
