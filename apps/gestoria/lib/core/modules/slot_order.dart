/// Pořadí widgetů ve slotu z `tenant_settings.slot_order`. Ne layout engine.
const carpetaBlocksSlot = 'carpeta.blocks';

List<String> slotKeys(Object? slotOrder, String slot) {
  if (slotOrder is! Map) return const [];
  final raw = slotOrder[slot];
  if (raw is! List) return const [];
  return [for (final v in raw) '$v'.trim()].where((s) => s.isNotEmpty).toList();
}

/// Klíče z [order] první, zbytek v původním pořadí katalogu.
List<T> applySlotOrder<T>({
  required List<T> items,
  required List<String> order,
  required String Function(T) keyOf,
}) {
  if (order.isEmpty) return List<T>.from(items);
  final byKey = <String, T>{for (final i in items) keyOf(i): i};
  final out = <T>[];
  final seen = <String>{};
  for (final k in order) {
    final item = byKey[k];
    if (item == null || !seen.add(k)) continue;
    out.add(item);
  }
  for (final i in items) {
    if (seen.add(keyOf(i))) out.add(i);
  }
  return out;
}

List<String> moveKey(List<String> keys, int index, int delta) {
  final next = List<String>.from(keys);
  final dest = index + delta;
  if (index < 0 || index >= next.length) return next;
  if (dest < 0 || dest >= next.length) return next;
  final item = next.removeAt(index);
  next.insert(dest, item);
  return next;
}
