import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/time/office_date.dart';
import '../inbox/inbox_providers.dart';
import 'expiring_campaign.dart';
import 'office_packs.dart';

class ClienteChannel {
  const ClienteChannel({required this.hasEmail, required this.hasTel});

  final bool hasEmail;
  final bool hasTel;
}

class BloqueStamp {
  const BloqueStamp({
    required this.id,
    required this.expedienteId,
    required this.templateKey,
    this.lastRequestedAt,
  });

  final String id;
  final String expedienteId;
  final String templateKey;
  final DateTime? lastRequestedAt;
}

PedirDraftRequest season210PedirRequest(
  Season210Row row, {
  required ClienteChannel? channel,
  DateTime? lastRequestedAt,
  required String documentoLabel,
}) {
  final missing = row.missingDocs.isNotEmpty;
  return PedirDraftRequest(
    clienteId: row.clienteId,
    clienteNombre: row.clienteNombre,
    templateKey: missing ? 'falta_documento' : 'recordatorio',
    bloqueKey: 'modelo_210',
    bloqueId: row.bloqueId,
    lastRequestedAt: lastRequestedAt,
    hasEmail: channel?.hasEmail ?? false,
    hasTel: channel?.hasTel ?? false,
    fecha: packFecha(row.dueOn),
    documento: documentoLabel,
  );
}

PedirDraftRequest afterNotaryPedirRequest(
  AfterNotaryRow row, {
  required ClienteChannel? channel,
  BloqueStamp? stamp,
}) {
  final addr = (row.direccion ?? '').trim();
  return PedirDraftRequest(
    clienteId: row.clienteId,
    clienteNombre: row.clienteNombre,
    templateKey: draftTemplateForNotary(row.tasks),
    bloqueKey: draftBloqueForNotary(row.tasks),
    bloqueId: stamp?.id,
    lastRequestedAt: stamp?.lastRequestedAt,
    hasEmail: channel?.hasEmail ?? false,
    hasTel: channel?.hasTel ?? false,
    fecha: packFecha(row.escrituraFecha),
    inmueble: addr.isEmpty ? '—' : addr,
  );
}

String packFecha(String? raw) {
  final parsed = parseOfficeDate(raw ?? '');
  if (parsed == null) {
    final t = (raw ?? '').trim();
    return t.isEmpty ? '—' : t;
  }
  final iso = inboxFechaIso(parsed);
  return iso.isEmpty ? '—' : iso;
}

BloqueStamp? stampForNotary(
  AfterNotaryRow row,
  Iterable<BloqueStamp> stamps,
) {
  final key = draftBloqueForNotary(row.tasks);
  final expedienteIds = {
    row.expedienteId,
    if ((row.taxExpedienteId ?? '').isNotEmpty) row.taxExpedienteId!,
  };
  for (final stamp in stamps) {
    if (stamp.templateKey == key && expedienteIds.contains(stamp.expedienteId)) {
      return stamp;
    }
  }
  return null;
}

Future<Map<String, ClienteChannel>> fetchClienteChannels(
  Iterable<String> clienteIds,
) async {
  final ids = {
    for (final id in clienteIds)
      if (id.trim().isNotEmpty) id.trim(),
  }.toList();
  if (ids.isEmpty) return {};
  final client = trySupabaseClient();
  if (client == null) return {};
  final rows = await client
      .from('clientes')
      .select('id, email, tel')
      .inFilter('id', ids)
      .isFilter('deleted_at', null);
  final out = <String, ClienteChannel>{};
  for (final raw in rows) {
    final id = '${raw['id'] ?? ''}'.trim();
    if (id.isEmpty) continue;
    out[id] = ClienteChannel(
      hasEmail: '${raw['email'] ?? ''}'.trim().isNotEmpty,
      hasTel: '${raw['tel'] ?? ''}'.trim().isNotEmpty,
    );
  }
  try {
    final contacts = await client
        .from('client_contacts')
        .select('cliente_id, email, tel')
        .inFilter('cliente_id', ids)
        .isFilter('deleted_at', null);
    for (final raw in contacts) {
      final id = '${raw['cliente_id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      final prev = out[id] ?? const ClienteChannel(hasEmail: false, hasTel: false);
      out[id] = ClienteChannel(
        hasEmail: prev.hasEmail || '${raw['email'] ?? ''}'.trim().isNotEmpty,
        hasTel: prev.hasTel || '${raw['tel'] ?? ''}'.trim().isNotEmpty,
      );
    }
  } on Object {
    // Kontakty nesmí shodit Pedir z karty.
  }
  return out;
}

Future<Map<String, DateTime?>> fetchBloqueLastRequested(
  Iterable<String> bloqueIds,
) async {
  final ids = {
    for (final id in bloqueIds)
      if (id.trim().isNotEmpty) id.trim(),
  }.toList();
  if (ids.isEmpty) return {};
  final client = trySupabaseClient();
  if (client == null) return {};
  final rows = await client
      .from('bloques')
      .select('id, last_requested_at')
      .inFilter('id', ids)
      .isFilter('deleted_at', null);
  final out = <String, DateTime?>{};
  for (final raw in rows) {
    final id = '${raw['id'] ?? ''}'.trim();
    if (id.isEmpty) continue;
    out[id] = DateTime.tryParse('${raw['last_requested_at'] ?? ''}');
  }
  return out;
}

Future<List<BloqueStamp>> fetchBloqueStamps(
  Iterable<String> expedienteIds,
) async {
  final ids = {
    for (final id in expedienteIds)
      if (id.trim().isNotEmpty) id.trim(),
  }.toList();
  if (ids.isEmpty) return const [];
  final client = trySupabaseClient();
  if (client == null) return const [];
  final rows = await client
      .from('bloques')
      .select('id, expediente_id, template_key, last_requested_at')
      .inFilter('expediente_id', ids)
      .isFilter('deleted_at', null);
  final out = <BloqueStamp>[];
  for (final raw in rows) {
    final id = '${raw['id'] ?? ''}'.trim();
    final expedienteId = '${raw['expediente_id'] ?? ''}'.trim();
    final templateKey = '${raw['template_key'] ?? ''}'.trim();
    if (id.isEmpty || expedienteId.isEmpty || templateKey.isEmpty) continue;
    out.add(
      BloqueStamp(
        id: id,
        expedienteId: expedienteId,
        templateKey: templateKey,
        lastRequestedAt:
            DateTime.tryParse('${raw['last_requested_at'] ?? ''}'),
      ),
    );
  }
  return out;
}

Future<List<PedirDraftRequest>> season210PedirRequests(
  List<Season210Row> rows, {
  required String Function(Season210Row row) documentoLabel,
}) async {
  final channels = await fetchClienteChannels(rows.map((r) => r.clienteId));
  final lasts = await fetchBloqueLastRequested(
    rows.map((r) => r.bloqueId).whereType<String>(),
  );
  return [
    for (final row in rows)
      season210PedirRequest(
        row,
        channel: channels[row.clienteId],
          lastRequestedAt:
              row.bloqueId == null ? null : lasts[row.bloqueId!],
        documentoLabel: documentoLabel(row),
      ),
  ];
}

Future<List<PedirDraftRequest>> afterNotaryPedirRequests(
  List<AfterNotaryRow> rows,
) async {
  final channels = await fetchClienteChannels(rows.map((r) => r.clienteId));
  final stamps = await fetchBloqueStamps([
    for (final row in rows) ...[
      row.expedienteId,
      if ((row.taxExpedienteId ?? '').isNotEmpty) row.taxExpedienteId!,
    ],
  ]);
  return [
    for (final row in rows)
      afterNotaryPedirRequest(
        row,
        channel: channels[row.clienteId],
        stamp: stampForNotary(row, stamps),
      ),
  ];
}

PedirDraftRequest seasonIbiPedirRequest(
  Season210Row row, {
  required ClienteChannel? channel,
  DateTime? lastRequestedAt,
  required String documentoLabel,
}) {
  final missing = row.missingDocs.isNotEmpty;
  return PedirDraftRequest(
    clienteId: row.clienteId,
    clienteNombre: row.clienteNombre,
    templateKey: missing ? 'falta_documento' : 'recordatorio',
    bloqueKey: 'suma',
    bloqueId: row.bloqueId,
    lastRequestedAt: lastRequestedAt,
    hasEmail: channel?.hasEmail ?? false,
    hasTel: channel?.hasTel ?? false,
    fecha: packFecha(row.dueOn),
    documento: documentoLabel,
  );
}

Future<List<PedirDraftRequest>> seasonIbiPedirRequests(
  List<Season210Row> rows, {
  required String Function(Season210Row row) documentoLabel,
}) async {
  final channels = await fetchClienteChannels(rows.map((r) => r.clienteId));
  final lasts = await fetchBloqueLastRequested(
    rows.map((r) => r.bloqueId).whereType<String>(),
  );
  return [
    for (final row in rows)
      seasonIbiPedirRequest(
        row,
        channel: channels[row.clienteId],
        lastRequestedAt: row.bloqueId == null ? null : lasts[row.bloqueId!],
        documentoLabel: documentoLabel(row),
      ),
  ];
}

Future<List<PedirDraftRequest>> expiringPedirRequests(
  List<ExpiringRow> rows,
) async {
  final channels = await fetchClienteChannels(rows.map((r) => r.clienteId));
  return [
    for (final row in rows)
      expiringPedirRequest(
        row,
        hasEmail: channels[row.clienteId]?.hasEmail,
        hasTel: channels[row.clienteId]?.hasTel,
      ),
  ];
}
