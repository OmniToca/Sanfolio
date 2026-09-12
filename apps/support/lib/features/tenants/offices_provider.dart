import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

class OfficeRow {
  const OfficeRow({
    required this.id,
    required this.name,
    this.displayName,
  });

  final String id;
  final String name;
  final String? displayName;

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
      .select('id, name, tenant_settings(display_name)')
      .isFilter('deleted_at', null)
      .order('created_at', ascending: false);
  final out = <OfficeRow>[];
  for (final raw in rows as List) {
    if (raw is! Map) continue;
    final settings = raw['tenant_settings'];
    String? display;
    if (settings is Map) {
      display = '${settings['display_name'] ?? ''}'.trim();
      if (display.isEmpty) display = null;
    } else if (settings is List && settings.isNotEmpty && settings.first is Map) {
      display = '${(settings.first as Map)['display_name'] ?? ''}'.trim();
      if (display.isEmpty) display = null;
    }
    out.add(
      OfficeRow(
        id: '${raw['id']}',
        name: '${raw['name'] ?? ''}',
        displayName: display,
      ),
    );
  }
  return out;
});
