import '../../core/time/office_date.dart';
import '../inbox/pedir.dart';

const expiringCampaignKinds = <String>[
  'dni_nie',
  'pasaporte',
  'poder',
  'seguro',
];

/// Řádek kampaně expirací. RPC je zdroj, Dart jen čte.
class ExpiringRow {
  const ExpiringRow({
    required this.clienteId,
    required this.clienteNombre,
    required this.kind,
    required this.expiresOn,
    required this.tone,
    this.bloqueId,
    this.expedienteId,
    this.documentoId,
    this.hasEmail = true,
    this.hasTel = true,
    this.lastRequestedAt,
  });

  final String clienteId;
  final String clienteNombre;
  final String kind;
  final String expiresOn;
  /// expired | expiring — stejná sémantika jako chip na kartě.
  final String tone;
  final String? bloqueId;
  final String? expedienteId;
  final String? documentoId;
  final bool hasEmail;
  final bool hasTel;
  final DateTime? lastRequestedAt;

  bool get isExpired => tone == 'expired';
}

/// Stejné okno jako chip: prošlé, nebo do [warnDays]. OCR odpad = mimo kampaň.
bool expiringInCampaign({
  required String raw,
  required DateTime today,
  required int warnDays,
}) {
  final tone = expiryTone(raw: raw, today: today, warnDays: warnDays);
  return tone == ExpiryTone.expired || tone == ExpiryTone.expiring;
}

int warnDaysForExpiringKind(String kind, {required int poder, required int seguro}) {
  return kind == 'seguro' ? seguro : poder;
}

/// DNI/pas vždy. Poder a seguro jen se zapnutým modulem.
bool expiringKindVisible(
  String kind, {
  required bool niePoderOn,
  required bool carpetaOn,
}) {
  return switch (kind) {
    'poder' => niePoderOn,
    'seguro' => carpetaOn,
    'dni_nie' || 'pasaporte' => true,
    _ => false,
  };
}

/// Španělský papír ve výzvě. Staff i18n sem nepatří.
String expiringBloqueLabel(String kind) {
  return switch (kind) {
    'dni_nie' => 'DNI / NIE',
    'pasaporte' => 'Pasaporte',
    'poder' => 'Poder',
    'seguro' => 'Seguro',
    _ => kind,
  };
}

PedirDraftRequest expiringPedirRequest(
  ExpiringRow row, {
  bool? hasEmail,
  bool? hasTel,
}) {
  final label = expiringBloqueLabel(row.kind);
  return PedirDraftRequest(
    clienteId: row.clienteId,
    clienteNombre: row.clienteNombre,
    templateKey: row.isExpired ? 'vencido' : 'recordatorio',
    bloqueKey: label,
    bloqueId: row.bloqueId,
    lastRequestedAt: row.lastRequestedAt,
    hasEmail: hasEmail ?? row.hasEmail,
    hasTel: hasTel ?? row.hasTel,
    fecha: row.expiresOn,
    documento: label,
  );
}

ExpiringRow? expiringRowFromRpc(Map raw) {
  final clienteId = '${raw['cliente_id'] ?? ''}'.trim();
  final kind = '${raw['kind'] ?? ''}'.trim();
  final expiresOn = '${raw['expires_on'] ?? ''}'.trim();
  final tone = '${raw['tone'] ?? ''}'.trim();
  if (clienteId.isEmpty ||
      !expiringCampaignKinds.contains(kind) ||
      expiresOn.isEmpty ||
      (tone != 'expired' && tone != 'expiring')) {
    return null;
  }
  final bloqueId = '${raw['bloque_id'] ?? ''}'.trim();
  final expedienteId = '${raw['expediente_id'] ?? ''}'.trim();
  final documentoId = '${raw['documento_id'] ?? ''}'.trim();
  return ExpiringRow(
    clienteId: clienteId,
    clienteNombre: '${raw['cliente_nombre'] ?? ''}'.trim(),
    kind: kind,
    expiresOn: expiresOn.length >= 10 ? expiresOn.substring(0, 10) : expiresOn,
    tone: tone,
    bloqueId: bloqueId.isEmpty ? null : bloqueId,
    expedienteId: expedienteId.isEmpty ? null : expedienteId,
    documentoId: documentoId.isEmpty ? null : documentoId,
    hasEmail: raw['has_email'] != false,
    hasTel: raw['has_tel'] != false,
    lastRequestedAt: DateTime.tryParse('${raw['last_requested_at'] ?? ''}'),
  );
}
