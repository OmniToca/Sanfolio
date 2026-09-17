import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import 'office_citas.dart';

/// Den v přehledu cit. Default dnes — kancelář přepne date pickerem.
final citasOnProvider = StateProvider<DateTime>((ref) => officeDayToday());

/// Počet cit **dnes** pro slot `inbox.feed`. Jiný den v přehledu banner nemění.
final citasTodayCountProvider = FutureProvider<int>((ref) async {
  ref.watch(authControllerProvider);
  final timer = Timer(const Duration(seconds: 20), () {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);
  final client = trySupabaseClient();
  final tenantId = ref
      .read(authControllerProvider)
      .valueOrNull
      ?.currentTenantId;
  if (client == null || tenantId == null) return 0;
  final n = await client.rpc(
    'office_citas_count',
    params: {'p_tenant_id': tenantId, 'p_on': officeDayIso(officeDayToday())},
  );
  return n is int ? n : int.tryParse('$n') ?? 0;
});

final citasListProvider = FutureProvider<List<OfficeCitaRow>>((ref) async {
  ref.watch(authControllerProvider);
  final on = ref.watch(citasOnProvider);
  final client = trySupabaseClient();
  final tenantId = ref
      .read(authControllerProvider)
      .valueOrNull
      ?.currentTenantId;
  if (client == null || tenantId == null) return const [];
  final rows = await client.rpc(
    'office_citas',
    params: {'p_tenant_id': tenantId, 'p_on': officeDayIso(on)},
  );
  final out = <OfficeCitaRow>[];
  if (rows is! List) return out;
  for (final raw in rows) {
    if (raw is! Map) continue;
    final row = officeCitaRowFromRpc(Map<String, dynamic>.from(raw));
    if (row != null) out.add(row);
  }
  return out;
});
