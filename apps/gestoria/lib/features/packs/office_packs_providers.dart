import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import 'office_packs.dart';

/// Počet otevřených 210 bez podání — slot `inbox.feed`.
final season210CountProvider = FutureProvider<int>((ref) async {
  return _count(ref, 'season_210_count');
});

final season210ListProvider = FutureProvider<List<Season210Row>>((ref) async {
  ref.watch(authControllerProvider);
  final rows = await _rpc(ref, 'season_210');
  final out = <Season210Row>[];
  for (final raw in rows) {
    final row = season210RowFromRpc(raw);
    if (row != null) out.add(row);
  }
  return out;
});

/// Počet koupi, kde po escritura zbývá práce.
final afterNotaryCountProvider = FutureProvider<int>((ref) async {
  return _count(ref, 'after_notary_count');
});

final afterNotaryListProvider = FutureProvider<List<AfterNotaryRow>>((ref) async {
  ref.watch(authControllerProvider);
  final rows = await _rpc(ref, 'after_notary');
  final out = <AfterNotaryRow>[];
  for (final raw in rows) {
    final row = afterNotaryRowFromRpc(raw);
    if (row != null) out.add(row);
  }
  return out;
});

Future<int> _count(Ref ref, String fn) async {
  ref.watch(authControllerProvider);
  final timer = Timer(const Duration(seconds: 20), () {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return 0;
  final n = await client.rpc(fn, params: {'p_tenant_id': tenantId});
  return n is int ? n : int.tryParse('$n') ?? 0;
}

Future<List<Map<String, dynamic>>> _rpc(Ref ref, String fn) async {
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return const [];
  final rows = await client.rpc(fn, params: {'p_tenant_id': tenantId});
  if (rows is! List) return const [];
  return [
    for (final raw in rows)
      if (raw is Map) Map<String, dynamic>.from(raw),
  ];
}
