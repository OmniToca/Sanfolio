import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/modules/slot_order.dart';

/// Lhůty a název kanceláře. Čte/zapisuje `tenant_settings`, žádný hardcoded tenant.
class OfficeSettings {
  const OfficeSettings({
    this.displayName = '',
    this.plusvaliaDays = 30,
    this.ibiWarnDays = 60,
    this.ibiDueMonth = 0,
    this.ibiDueDay = 0,
    this.seguroWarnDays = 60,
    this.alarmaWarnDays = 60,
    this.poderWarnDays = 60,
    this.nudgeIntervalDays = 7,
    this.staleExpedienteDays = 14,
    this.sendTranslatedOutbound = true,
    this.slotOrder = const {},
    this.emisorNif = '',
    this.emisorNombre = '',
    this.facturaSerie = 'A',
    this.officeEmail = '',
    this.officePhone = '',
  });

  final String displayName;
  final int plusvaliaDays;
  final int ibiWarnDays;
  /// 0 = kancelář ještě nenastavila splatnost IBI (žádné 1. 11. v kódu).
  final int ibiDueMonth;
  final int ibiDueDay;
  final int seguroWarnDays;
  final int alarmaWarnDays;
  final int poderWarnDays;
  final int nudgeIntervalDays;
  final int staleExpedienteDays;
  final bool sendTranslatedOutbound;
  final Map<String, dynamic> slotOrder;
  final String emisorNif;
  final String emisorNombre;
  final String facturaSerie;
  final String officeEmail;
  final String officePhone;

  bool get ibiDueConfigured =>
      ibiDueMonth >= 1 && ibiDueMonth <= 12 && ibiDueDay >= 1 && ibiDueDay <= 31;

  OfficeSettings copyWith({
    String? displayName,
    int? plusvaliaDays,
    int? ibiWarnDays,
    int? ibiDueMonth,
    int? ibiDueDay,
    int? seguroWarnDays,
    int? alarmaWarnDays,
    int? poderWarnDays,
    int? nudgeIntervalDays,
    int? staleExpedienteDays,
    bool? sendTranslatedOutbound,
    Map<String, dynamic>? slotOrder,
    String? emisorNif,
    String? emisorNombre,
    String? facturaSerie,
    String? officeEmail,
    String? officePhone,
  }) {
    return OfficeSettings(
      displayName: displayName ?? this.displayName,
      plusvaliaDays: plusvaliaDays ?? this.plusvaliaDays,
      ibiWarnDays: ibiWarnDays ?? this.ibiWarnDays,
      ibiDueMonth: ibiDueMonth ?? this.ibiDueMonth,
      ibiDueDay: ibiDueDay ?? this.ibiDueDay,
      seguroWarnDays: seguroWarnDays ?? this.seguroWarnDays,
      alarmaWarnDays: alarmaWarnDays ?? this.alarmaWarnDays,
      poderWarnDays: poderWarnDays ?? this.poderWarnDays,
      nudgeIntervalDays: nudgeIntervalDays ?? this.nudgeIntervalDays,
      staleExpedienteDays: staleExpedienteDays ?? this.staleExpedienteDays,
      sendTranslatedOutbound:
          sendTranslatedOutbound ?? this.sendTranslatedOutbound,
      slotOrder: slotOrder ?? this.slotOrder,
      emisorNif: emisorNif ?? this.emisorNif,
      emisorNombre: emisorNombre ?? this.emisorNombre,
      facturaSerie: facturaSerie ?? this.facturaSerie,
      officeEmail: officeEmail ?? this.officeEmail,
      officePhone: officePhone ?? this.officePhone,
    );
  }

  static OfficeSettings fromRow(Map<dynamic, dynamic> row) {
    return OfficeSettings(
      displayName: _displayName(row),
      plusvaliaDays: _int(row['plusvalia_days'], 30),
      ibiWarnDays: _int(row['ibi_warn_days'], 60),
      ibiDueMonth: _int(row['ibi_due_month'], 0),
      ibiDueDay: _int(row['ibi_due_day'], 0),
      seguroWarnDays: _int(row['seguro_warn_days'], 60),
      alarmaWarnDays: _int(row['alarma_warn_days'], 60),
      poderWarnDays: _int(row['poder_warn_days'], 60),
      nudgeIntervalDays: _int(row['nudge_interval_days'], 7),
      staleExpedienteDays: _int(row['stale_expediente_days'], 14),
      sendTranslatedOutbound: row['send_translated_outbound'] != false,
      slotOrder: _map(row['slot_order']),
      emisorNif: '${row['emisor_nif'] ?? ''}'.trim(),
      emisorNombre: '${row['emisor_nombre'] ?? ''}'.trim(),
      facturaSerie: _serie(row['factura_serie']),
      officeEmail: '${row['office_email'] ?? ''}'.trim(),
      officePhone: '${row['office_phone'] ?? ''}'.trim(),
    );
  }

  static String _displayName(Map<dynamic, dynamic> row) {
    final display = '${row['display_name'] ?? ''}'.trim();
    if (display.isNotEmpty) return display;
    final tenants = row['tenants'];
    if (tenants is Map) {
      return '${tenants['name'] ?? ''}'.trim();
    }
    return '';
  }

  static String _serie(Object? value) {
    final s = '${value ?? ''}'.trim();
    return s.isEmpty ? 'A' : s;
  }

  static int _int(Object? value, int fallback) {
    if (value is int) return value;
    return int.tryParse('$value') ?? fallback;
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) {
      return {
        for (final e in value.entries) '${e.key}': e.value,
      };
    }
    return {};
  }
}

class OfficeSettingsController extends AsyncNotifier<OfficeSettings> {
  String? _tenantId;

  @override
  Future<OfficeSettings> build() async {
    final auth = await ref.watch(authControllerProvider.future);
    final tenantId = auth.currentTenantId;
    _tenantId = tenantId;
    if (tenantId == null) {
      throw const MissingOfficeTenant();
    }
    final client = trySupabaseClient();
    if (client == null) {
      throw StateError('not configured');
    }
    final row = await client
        .from('tenant_settings')
        .select(
          'display_name, plusvalia_days, ibi_warn_days, ibi_due_month, '
          'ibi_due_day, seguro_warn_days, '
          'alarma_warn_days, poder_warn_days, send_translated_outbound, '
          'nudge_interval_days, stale_expediente_days, slot_order, '
          'emisor_nif, emisor_nombre, factura_serie, office_email, office_phone',
        )
        .eq('tenant_id', tenantId)
        .maybeSingle();
    var settings = row == null
        ? const OfficeSettings()
        : OfficeSettings.fromRow(row);
    if (settings.displayName.isEmpty) {
      final tenant = await client
          .from('tenants')
          .select('name')
          .eq('id', tenantId)
          .maybeSingle();
      settings = settings.copyWith(
        displayName: '${tenant?['name'] ?? ''}'.trim(),
      );
    }
    return settings;
  }

  Future<void> setPlusvaliaDays(int v) =>
      _patch({'plusvalia_days': v}, (s) => s.copyWith(plusvaliaDays: v));

  Future<void> setIbiWarnDays(int v) =>
      _patch({'ibi_warn_days': v}, (s) => s.copyWith(ibiWarnDays: v));

  Future<void> setIbiDueMonth(int v) => _patch(
        {'ibi_due_month': v == 0 ? null : v},
        (s) => s.copyWith(ibiDueMonth: v),
      );

  Future<void> setIbiDueDay(int v) => _patch(
        {'ibi_due_day': v == 0 ? null : v},
        (s) => s.copyWith(ibiDueDay: v),
      );

  Future<void> setSeguroWarnDays(int v) =>
      _patch({'seguro_warn_days': v}, (s) => s.copyWith(seguroWarnDays: v));

  Future<void> setAlarmaWarnDays(int v) =>
      _patch({'alarma_warn_days': v}, (s) => s.copyWith(alarmaWarnDays: v));

  Future<void> setPoderWarnDays(int v) =>
      _patch({'poder_warn_days': v}, (s) => s.copyWith(poderWarnDays: v));

  Future<void> setNudgeIntervalDays(int v) => _patch(
        {'nudge_interval_days': v},
        (s) => s.copyWith(nudgeIntervalDays: v),
      );

  Future<void> setStaleExpedienteDays(int v) => _patch(
        {'stale_expediente_days': v},
        (s) => s.copyWith(staleExpedienteDays: v),
      );

  Future<void> setSendTranslatedOutbound(bool v) => _patch(
        {'send_translated_outbound': v},
        (s) => s.copyWith(sendTranslatedOutbound: v),
      );

  Future<void> setCarpetaBlocksOrder(List<String> keys) {
    final next = Map<String, dynamic>.from(state.valueOrNull?.slotOrder ?? {});
    next[carpetaBlocksSlot] = keys;
    return _patch({'slot_order': next}, (s) => s.copyWith(slotOrder: next));
  }

  Future<void> setEmisorNif(String v) =>
      _patch({'emisor_nif': v.trim()}, (s) => s.copyWith(emisorNif: v.trim()));

  Future<void> setEmisorNombre(String v) => _patch(
        {'emisor_nombre': v.trim()},
        (s) => s.copyWith(emisorNombre: v.trim()),
      );

  Future<void> setOfficeEmail(String v) => _patch(
        {'office_email': v.trim()},
        (s) => s.copyWith(officeEmail: v.trim()),
      );

  Future<void> setOfficePhone(String v) => _patch(
        {'office_phone': v.trim()},
        (s) => s.copyWith(officePhone: v.trim()),
      );

  Future<void> setFacturaSerie(String v) {
    final serie = v.trim().isEmpty ? 'A' : v.trim();
    return _patch({'factura_serie': serie}, (s) => s.copyWith(facturaSerie: serie));
  }

  Future<void> _patch(
    Map<String, Object?> row,
    OfficeSettings Function(OfficeSettings) apply,
  ) async {
    final current = state.valueOrNull;
    final tenantId = _tenantId;
    final client = trySupabaseClient();
    if (current == null || tenantId == null || client == null) return;
    state = AsyncData(apply(current));
    try {
      await client.from('tenant_settings').update(row).eq('tenant_id', tenantId);
    } on Object {
      state = AsyncData(current);
    }
  }
}

/// Chybí impersonace i členství — nastavení nemá z koho číst.
class MissingOfficeTenant implements Exception {
  const MissingOfficeTenant();
}

final officeSettingsProvider =
    AsyncNotifierProvider<OfficeSettingsController, OfficeSettings>(
  OfficeSettingsController.new,
);
