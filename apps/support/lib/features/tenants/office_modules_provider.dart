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

/// Ceník katalogu. Support bez impersonace.
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

/// Katalog + licence jedné kanceláře. Support bez impersonace.
final supportOfficeLicenceProvider =
    FutureProvider.family<LicenceQuote, String>((ref, tenantId) async {
  final client = trySupabaseClient();
  if (client == null) return const LicenceQuote(lines: []);
  final catalog = await ref.watch(moduleCatalogProvider.future);
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
  return LicenceQuote(
    discountBps: discount,
    lines: [
      for (final row in catalog)
        if (row.key != 'client_portal')
          LicenceLine(
            key: row.key,
            cents: row.cents,
            alwaysOn: row.alwaysOn,
            on: row.alwaysOn || live.contains(row.key),
          ),
    ],
  );
});

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
