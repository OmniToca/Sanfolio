import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import 'office_offers.dart';

/// Počet přeplatků pro slot `inbox.feed`.
final overpayCountProvider = FutureProvider<int>((ref) async {
  ref.watch(authControllerProvider);
  final timer = Timer(const Duration(seconds: 20), () {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return 0;
  final n = await client.rpc(
    'overpaying_suministro_count',
    params: {'p_tenant_id': tenantId},
  );
  return n is int ? n : int.tryParse('$n') ?? 0;
});

/// Office-wide: uložené faktury vs. tarify kanceláře.
final overpayListProvider = FutureProvider<List<OverpayRow>>((ref) async {
  ref.watch(authControllerProvider);
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return const [];
  final rows = await client.rpc(
    'overpaying_suministro',
    params: {'p_tenant_id': tenantId},
  );
  final out = <OverpayRow>[];
  if (rows is! List) return out;
  for (final raw in rows) {
    if (raw is! Map) continue;
    final row = overpayRowFromRpc(Map<String, dynamic>.from(raw));
    if (row != null) out.add(row);
  }
  return out;
});
