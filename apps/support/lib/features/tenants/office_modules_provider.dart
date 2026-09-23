import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import 'office_licence.dart';

class CatalogPrice {
  const CatalogPrice({
    required this.key,
    required this.cents,
    required this.alwaysOn,
  });

  final String key;
  final int cents;
  final bool alwaysOn;
}

/// Ceník modulů (doplňky). Support bez impersonace.
final moduleCatalogProvider = FutureProvider<List<CatalogPrice>>((ref) async {
  final client = trySupabaseClient();
  if (client == null) return [];
  final catalog = await client
      .from('modules')
      .select('key, always_on, monthly_cents, sort_order')
      .order('sort_order');
  final out = <CatalogPrice>[];
  for (final raw in catalog as List) {
    if (raw is! Map) continue;
    final key = '${raw['key']}';
    if (key.isEmpty) continue;
    out.add(
      CatalogPrice(
        key: key,
        cents: (raw['monthly_cents'] as num?)?.toInt() ?? 0,
        alwaysOn: raw['always_on'] == true,
      ),
    );
  }
  return out;
});

/// Ceník 3 balíčků + included z DB.
final licencePlansProvider = FutureProvider<List<LicencePlanInfo>>((ref) async {
  final client = trySupabaseClient();
  if (client == null) return _fallbackPlans();
  try {
    final plans = await client
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
    final out = <LicencePlanInfo>[];
    for (final raw in plans as List) {
      if (raw is! Map) continue;
      final key = '${raw['key']}';
      if (key.isEmpty) continue;
      out.add(
        LicencePlanInfo(
          key: key,
          cents: (raw['monthly_cents'] as num?)?.toInt() ?? 0,
          includedKeys: included[key] ?? includedKeysForPlan(key),
        ),
      );
    }
    if (out.isEmpty) return _fallbackPlans();
    return out;
  } on Object {
    return _fallbackPlans();
  }
});

List<LicencePlanInfo> _fallbackPlans() {
  return [
    for (final key in LicencePlanKeys.all)
      LicencePlanInfo(
        key: key,
        cents: 0,
        includedKeys: includedKeysForPlan(key),
      ),
  ];
}

/// Katalog + licence jedné kanceláře. Support bez impersonace.
final supportOfficeLicenceProvider =
    FutureProvider.family<LicenceQuote, String>((ref, tenantId) async {
  final client = trySupabaseClient();
  if (client == null) return const LicenceQuote();
  final catalog = await ref.watch(moduleCatalogProvider.future);
  final plans = await ref.watch(licencePlansProvider.future);
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
  return resolveLicenceQuote(
    plans: plans,
    planKey: planKey,
    liveKeys: live,
    catalog: [
      for (final row in catalog)
        ModulePrice(key: row.key, cents: row.cents, alwaysOn: row.alwaysOn),
    ],
    discountBps: discount,
  );
});

Future<void> setSupportOfficePlan({
  required String tenantId,
  required String planKey,
}) async {
  final client = trySupabaseClient();
  if (client == null) return;
  await client.rpc(
    'set_office_plan',
    params: {
      'p_tenant_id': tenantId,
      'p_plan_key': planKey,
    },
  );
}

Future<void> setSupportOfficeModule({
  required String tenantId,
  required String moduleKey,
  required bool on,
}) async {
  final client = trySupabaseClient();
  if (client == null) return;
  await client.rpc(
    'set_office_module',
    params: {
      'p_tenant_id': tenantId,
      'p_module_key': moduleKey,
      'p_on': on,
    },
  );
}

Future<void> setSupportOfficeDiscount({
  required String tenantId,
  required int discountBps,
}) async {
  final client = trySupabaseClient();
  if (client == null) return;
  await client.rpc(
    'set_office_discount',
    params: {
      'p_tenant_id': tenantId,
      'p_discount_bps': discountBps,
    },
  );
}

Future<void> setModuleCatalogPrice({
  required String moduleKey,
  required int cents,
}) async {
  final client = trySupabaseClient();
  if (client == null) return;
  await client.rpc(
    'set_module_monthly_cents',
    params: {
      'p_key': moduleKey,
      'p_cents': cents,
    },
  );
}

Future<void> setPlanCatalogPrice({
  required String planKey,
  required int cents,
}) async {
  final client = trySupabaseClient();
  if (client == null) return;
  await client.rpc(
    'set_plan_monthly_cents',
    params: {
      'p_key': planKey,
      'p_cents': cents,
    },
  );
}
