import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import 'office_licence.dart';

class OfficeRow {
  const OfficeRow({
    required this.id,
    required this.name,
    this.displayName,
    this.planKey = LicencePlanKeys.carpeta,
  });

  final String id;
  final String name;
  final String? displayName;
  final String planKey;

  String get label {
    final d = displayName?.trim();
    if (d != null && d.isNotEmpty && d != name) return '$d ($name)';
    return d != null && d.isNotEmpty ? d : name;
  }
}

final officesProvider = FutureProvider<List<OfficeRow>>((ref) async {
  ref.watch(authControllerProvider);
  final client = trySupabaseClient();
  if (client == null) return [];
  final rows = await client
      .from('tenants')
      .select('id, name, tenant_settings(display_name, licence_plan_key)')
      .isFilter('deleted_at', null)
      .order('created_at', ascending: false);
  final out = <OfficeRow>[];
  for (final raw in rows as List) {
    if (raw is! Map) continue;
    final settings = raw['tenant_settings'];
    String? display;
    var planKey = LicencePlanKeys.carpeta;
    Map? settingsMap;
    if (settings is Map) {
      settingsMap = settings;
    } else if (settings is List && settings.isNotEmpty && settings.first is Map) {
      settingsMap = settings.first as Map;
    }
    if (settingsMap != null) {
      display = '${settingsMap['display_name'] ?? ''}'.trim();
      if (display.isEmpty) display = null;
      final rawPlan = '${settingsMap['licence_plan_key'] ?? ''}'.trim();
      if (rawPlan.isNotEmpty) planKey = rawPlan;
    }
    out.add(
      OfficeRow(
        id: '${raw['id']}',
        name: '${raw['name'] ?? ''}',
        displayName: display,
        planKey: planKey,
      ),
    );
  }
  return out;
});
