import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/modules/office_licence.dart';

/// Co kancelář platí. Balíček a slevu mění jen Support HQ.
final officeLicenceProvider = FutureProvider<LicenceQuote>((ref) async {
  final auth = await ref.watch(authControllerProvider.future);
  final tenantId = auth.currentTenantId;
  final client = trySupabaseClient();
  if (tenantId == null || client == null) {
    return const LicenceQuote();
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
      .select('licence_discount_bps, licence_plan_key')
      .eq('tenant_id', tenantId)
      .maybeSingle();
  final discount = (settings?['licence_discount_bps'] as num?)?.toInt() ?? 0;
  final planKey = '${settings?['licence_plan_key'] ?? ''}';

  List<LicencePlanInfo> plans;
  try {
    final planRows = await client
        .from('licence_plans')
        .select('key, monthly_cents, sort_order')
        .order('sort_order');
    final features = await client
        .from('licence_plan_modules')
        .select('plan_key, module_key');
    final included = <String, Set<String>>{};
    for (final raw in features as List) {
      if (raw is! Map) continue;
      final plan = '${raw['plan_key']}';
      final module = '${raw['module_key']}';
      if (plan.isEmpty || module.isEmpty) continue;
      included.putIfAbsent(plan, () => <String>{}).add(module);
    }
    plans = [
      for (final raw in planRows as List)
        if (raw is Map && '${raw['key']}'.isNotEmpty)
          LicencePlanInfo(
            key: '${raw['key']}',
            cents: (raw['monthly_cents'] as num?)?.toInt() ?? 0,
            includedKeys:
                included['${raw['key']}'] ?? includedKeysForPlan('${raw['key']}'),
          ),
    ];
  } on Object {
    plans = [
      for (final key in LicencePlanKeys.all)
        LicencePlanInfo(
          key: key,
          cents: 0,
          includedKeys: includedKeysForPlan(key),
        ),
    ];
  }

  return resolveLicenceQuote(
    plans: plans,
    planKey: planKey,
    liveKeys: live,
    catalog: [
      for (final raw in catalog as List)
        if (raw is Map && '${raw['key']}'.isNotEmpty)
          ModulePrice(
            key: '${raw['key']}',
            cents: (raw['monthly_cents'] as num?)?.toInt() ?? 0,
            alwaysOn: raw['always_on'] == true,
          ),
    ],
    discountBps: discount,
  );
});
