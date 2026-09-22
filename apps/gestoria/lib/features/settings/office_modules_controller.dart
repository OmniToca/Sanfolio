import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/modules/office_licence.dart';

/// Co kancelář platí. Ceník a slevu mění jen Support HQ.
final officeLicenceProvider = FutureProvider<LicenceQuote>((ref) async {
  final auth = await ref.watch(authControllerProvider.future);
  final tenantId = auth.currentTenantId;
  final client = trySupabaseClient();
  if (tenantId == null || client == null) {
    return const LicenceQuote(lines: []);
  }
  final catalog = await client
      .from('modules')
      .select('key, always_on, monthly_cents, sort_order')
      .order('sort_order');
  final liveRows = await client
      .from('organization_modules')
      .select('module_key, status')
      .eq('tenant_id', tenantId)
      .isFilter('deleted_at', null);
  final live = <String>{};
  for (final raw in liveRows as List) {
    if (raw is! Map) continue;
    final status = '${raw['status']}';
    if (status != 'active' && status != 'trial') continue;
    live.add('${raw['module_key']}');
  }
  final settings = await client
      .from('tenant_settings')
      .select('licence_discount_bps')
      .eq('tenant_id', tenantId)
      .maybeSingle();
  final discount = (settings?['licence_discount_bps'] as num?)?.toInt() ?? 0;
  final lines = <LicenceLine>[];
  for (final raw in catalog as List) {
    if (raw is! Map) continue;
    final key = '${raw['key']}';
    if (key.isEmpty || key == 'client_portal') continue;
    final always = raw['always_on'] == true;
    final cents = (raw['monthly_cents'] as num?)?.toInt() ?? 0;
    lines.add(
      LicenceLine(
        key: key,
        cents: cents,
        alwaysOn: always,
        on: always || live.contains(key),
      ),
    );
  }
  return LicenceQuote(lines: lines, discountBps: discount);
});
