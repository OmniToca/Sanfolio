import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../carpeta/carpeta_controller.dart';
import 'ai_providers.dart';
import 'extract_queue.dart';

/// Počet čekajících přepisů pro slot `inbox.feed`.
final extractQueueCountProvider = FutureProvider<int>((ref) async {
  ref.watch(authControllerProvider);
  final timer = Timer(const Duration(seconds: 12), () {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return 0;
  final n = await client.rpc(
    'pending_extract_count',
    params: {'p_tenant_id': tenantId},
  );
  return n is int ? n : int.tryParse('$n') ?? 0;
});

/// Třídírna `/prepis`. Jen extract bez Guardar.
final extractQueueProvider = FutureProvider<List<ExtractQueueRow>>((ref) async {
  ref.watch(authControllerProvider);
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return const [];
  final rows = await client.rpc(
    'pending_extract_queue',
    params: {'p_tenant_id': tenantId},
  );
  final out = <ExtractQueueRow>[];
  if (rows is! List) return out;
  for (final raw in rows) {
    if (raw is! Map) continue;
    final row = extractQueueRowFromRpc(Map<String, dynamic>.from(raw));
    if (row != null) out.add(row);
  }
  if (out.any((r) => r.pending)) {
    final timer = Timer(const Duration(seconds: 2), () {
      ref.invalidateSelf();
    });
    ref.onDispose(timer.cancel);
  }
  return out;
});

void invalidateExtractQueue(WidgetRef ref) {
  ref.invalidate(extractQueueProvider);
  ref.invalidate(extractQueueCountProvider);
}

/// Stejný zápis jako na desce. AI sem nesmí.
Future<bool> applyExtractQueueRow({
  required WidgetRef ref,
  required ExtractQueueRow row,
}) async {
  if (!row.canGuardar) return false;
  final target = CarpetaTarget(
    clienteId: row.clienteId,
    expedienteId: row.expedienteId,
  );
  try {
    await ref.read(carpetaControllerProvider(target).future);
  } on Object {
    return false;
  }
  final ctrl = ref.read(carpetaControllerProvider(target).notifier);
  final view = ref.read(carpetaControllerProvider(target)).valueOrNull;
  final bloque = view?.bloques[row.bloqueKey];
  if (bloque != null && !bloque.enabled) {
    await ctrl.setEnabled(row.bloqueKey, true);
  }
  await ctrl.saveDocumentoExtracted(
    templateKey: row.bloqueKey,
    documentId: row.documentoId!,
    fields: row.fields,
  );
  await discardAiDraft(row.draftId);
  ref.invalidate(liveAiDraftsProvider(row.clienteId));
  invalidateExtractQueue(ref);
  return true;
}

Future<void> discardExtractQueueRow({
  required WidgetRef ref,
  required ExtractQueueRow row,
}) async {
  await discardAiDraft(row.draftId);
  ref.invalidate(liveAiDraftsProvider(row.clienteId));
  invalidateExtractQueue(ref);
}
