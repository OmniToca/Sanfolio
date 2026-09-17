import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import 'reach_gaps.dart';

final reachGapsCountProvider = FutureProvider<int>((ref) async {
  ref.watch(authControllerProvider);
  final timer = Timer(const Duration(seconds: 20), () {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return 0;
  final n = await client.rpc(
    'reach_gaps_count',
    params: {'p_tenant_id': tenantId},
  );
  return n is int ? n : int.tryParse('$n') ?? 0;
});

final reachGapsListProvider = FutureProvider<List<ReachGapRow>>((ref) async {
  ref.watch(authControllerProvider);
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return const [];
  final rows = await client.rpc(
    'reach_gaps',
    params: {'p_tenant_id': tenantId},
  );
  final out = <ReachGapRow>[];
  if (rows is! List) return out;
  for (final raw in rows) {
    if (raw is! Map) continue;
    final row = reachGapRowFromRpc(Map<String, dynamic>.from(raw));
    if (row != null) out.add(row);
  }
  return out;
});

Future<({bool email, bool tel, bool locale})> copyChannelFromContact(
  String clienteId,
) async {
  final client = trySupabaseClient();
  if (client == null) throw StateError('not configured');
  final raw = await client.rpc(
    'copy_channel_from_contact',
    params: {'p_cliente_id': clienteId},
  );
  Map<String, dynamic>? map;
  if (raw is Map) map = Map<String, dynamic>.from(raw);
  return (
    email: map?['email'] == true,
    tel: map?['tel'] == true,
    locale: map?['locale'] == true,
  );
}
