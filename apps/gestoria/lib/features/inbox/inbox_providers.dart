import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/time/office_date.dart';
import '../mensajes/mensaje_providers.dart';
import '../mensajes/mensaje_templates.dart';

class InboxRow {
  const InboxRow({
    required this.clienteId,
    required this.clienteNombre,
    required this.bloqueKey,
    required this.itemKind,
    this.dueOn,
    this.expedienteId,
    this.expedienteTipo,
    this.bloqueId,
    this.lastRequestedAt,
    this.hasEmail = true,
    this.hasTel = true,
    this.plazoId,
    this.plazoSource,
    this.plazoNote,
  });

  final String clienteId;
  final String clienteNombre;
  final String bloqueKey;
  final String itemKind;
  final DateTime? dueOn;
  final String? expedienteId;
  final String? expedienteTipo;
  final String? bloqueId;
  final DateTime? lastRequestedAt;
  final bool hasEmail;
  final bool hasTel;
  final String? plazoId;
  final String? plazoSource;
  final String? plazoNote;

  bool get hasChannel => hasEmail || hasTel;

  bool get canSnooze {
    final id = plazoId;
    return id != null && id.isNotEmpty;
  }

  /// Další Pedir až po `nudge_interval_days` od last_requested_at.
  bool canPedir({required int nudgeIntervalDays, DateTime? now}) {
    return canPedirAlCliente(
      lastRequestedAt: lastRequestedAt,
      nudgeIntervalDays: nudgeIntervalDays,
      now: now,
    );
  }
}

/// Čistá pravidla výzvy — cron i inbox používají stejný interval z tenant_settings.
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

String inboxFechaIso(DateTime? dueOn) {
  if (dueOn == null) return '';
  return '${dueOn.year.toString().padLeft(4, '0')}-'
      '${dueOn.month.toString().padLeft(2, '0')}-'
      '${dueOn.day.toString().padLeft(2, '0')}';
}

/// Inbox i cron: schovat, když snooze_until je po dnešku (date, Madrid).
bool isPlazoSnoozed({DateTime? snoozeUntil, required DateTime today}) {
  if (snoozeUntil == null) return false;
  return calendarDay(snoozeUntil).isAfter(calendarDay(today));
}

/// Ruční termín. Derived se touhle cestou nesahá.
Future<String> addManualPlazo({
  required String expedienteId,
  required DateTime dueOn,
  required String note,
  String? bloqueId,
}) async {
  final client = trySupabaseClient();
  if (client == null) throw StateError('not configured');
  final trimmed = note.trim();
  if (trimmed.isEmpty) throw ArgumentError('note');
  final raw = await client.rpc(
    'add_manual_plazo',
    params: {
      'p_expediente_id': expedienteId,
      'p_due_on': inboxFechaIso(dueOn),
      'p_note': trimmed,
      if (bloqueId != null && bloqueId.isNotEmpty) 'p_bloque_id': bloqueId,
    },
  );
  return '$raw'.trim();
}

/// Odklad. due_on a source zůstanou.
Future<void> snoozePlazo({
  required String plazoId,
  required DateTime until,
}) async {
  final client = trySupabaseClient();
  if (client == null) throw StateError('not configured');
  await client.rpc(
    'snooze_plazo',
    params: {
      'p_plazo_id': plazoId,
      'p_until': inboxFechaIso(until),
    },
  );
}

/// Razítko + draft. Odesílá jen gestor z compose, ne tahle funkce.
Future<void> pedirAlCliente({
  required String tenantId,
  required InboxRow row,
  required String despacho,
}) async {
  final client = trySupabaseClient();
  if (client == null) throw StateError('not configured');
  final bloqueId = row.bloqueId;
  if (bloqueId != null && bloqueId.isNotEmpty) {
    await client.from('bloques').update({
      'last_requested_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', bloqueId).eq('tenant_id', tenantId);
  }
  final tplKey = templateKeyForInboxKind(row.itemKind);
  final fecha = inboxFechaIso(row.dueOn);
  final filled = filledTemplate(
    key: tplKey,
    vars: {
      'nombre': row.clienteNombre,
      'bloque': row.bloqueKey,
      'documento': row.bloqueKey,
      'fecha': fecha.isEmpty ? '—' : fecha,
      'despacho': despacho,
      'inmueble': '—',
      'campos_faltantes': '—',
    },
  );
  await recordMensaje(
    tenantId: tenantId,
    clienteId: row.clienteId,
    canal: row.hasEmail ? 'email' : 'whatsapp',
    asunto: filled.asunto,
    cuerpoOriginal: filled.cuerpo,
    localeOriginal: 'es',
    outboundLocale: 'es',
    outboundBody: filled.cuerpo,
    status: 'draft',
    templateKey: tplKey,
    bloqueId: bloqueId,
  );
}

final inboxFeedProvider = FutureProvider<List<InboxRow>>((ref) async {
  ref.watch(authControllerProvider);
  final client = trySupabaseClient();
  if (client == null) return [];
  final rows = await client.rpc('inbox_feed');
  final out = <InboxRow>[];
  if (rows is! List) return out;
  for (final raw in rows) {
    if (raw is! Map) continue;
    DateTime? due;
    final dueRaw = raw['due_on'];
    if (dueRaw != null) {
      due = DateTime.tryParse('$dueRaw');
    }
    out.add(
      InboxRow(
        clienteId: '${raw['cliente_id']}',
        clienteNombre: '${raw['cliente_nombre'] ?? ''}'.trim(),
        bloqueKey: '${raw['bloque_key'] ?? ''}',
        itemKind: '${raw['item_kind'] ?? ''}',
        dueOn: due,
        expedienteId: raw['expediente_id'] == null
            ? null
            : '${raw['expediente_id']}',
        expedienteTipo: raw['expediente_tipo'] == null
            ? null
            : '${raw['expediente_tipo']}',
        bloqueId:
            raw['bloque_id'] == null ? null : '${raw['bloque_id']}',
        lastRequestedAt: raw['last_requested_at'] == null
            ? null
            : DateTime.tryParse('${raw['last_requested_at']}'),
        hasEmail: raw['has_email'] != false,
        hasTel: raw['has_tel'] != false,
        plazoId: raw['plazo_id'] == null ? null : '${raw['plazo_id']}',
        plazoSource:
            raw['plazo_source'] == null ? null : '${raw['plazo_source']}',
        plazoNote: raw['plazo_note'] == null
            ? null
            : '${raw['plazo_note']}'.trim(),
      ),
    );
  }
  return out;
});

/// Filtry dnešní smyčky. `no_channel` je příznak, ne item_kind.
const inboxFilterKeys = <String>[
  'all',
  'due_today',
  'overdue',
  'missing_document',
  'missing_data',
  'provision_alert',
  'stale_expediente',
  'no_channel',
];

bool matchesInboxFilter(InboxRow row, String filter) {
  return switch (filter) {
    'all' || '' => true,
    'no_channel' => !row.hasChannel,
    _ => row.itemKind == filter,
  };
}
