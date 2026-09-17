import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import 'office_offers.dart';

/// Nabídky kanceláře. Gestor je vyplní v Nastavení, AI sem nesahá.
final officeOffersProvider = FutureProvider<List<OfficeOffer>>((ref) async {
  ref.watch(authControllerProvider);
  final client = trySupabaseClient();
  final tenantId = ref.read(authControllerProvider).valueOrNull?.currentTenantId;
  if (client == null || tenantId == null) return const [];
  final rows = await client
      .from('office_offers')
      .select('id, kind, title, partner, unit_cents, annual_cents, notes')
      .eq('tenant_id', tenantId)
      .isFilter('deleted_at', null)
      .order('kind')
      .order('title');
  final out = <OfficeOffer>[];
  for (final raw in rows) {
    final o = officeOfferFromRow(Map<String, dynamic>.from(raw));
    if (o != null) out.add(o);
  }
  return out;
});

Future<bool> saveOfficeOffer({
  required String tenantId,
  required String kind,
  required String title,
  String partner = '',
  int? unitCents,
  int? annualCents,
  String notes = '',
  String? id,
}) async {
  final client = trySupabaseClient();
  if (client == null || title.trim().isEmpty) return false;
  if (!officeOfferKinds.contains(kind)) return false;
  if (unitCents == null && annualCents == null) return false;
  final uid = (await client.auth.getUser()).user?.id;
  final row = {
    'tenant_id': tenantId,
    'kind': kind,
    'title': title.trim(),
    'partner': partner.trim().isEmpty ? null : partner.trim(),
    'unit_cents': unitCents,
    'annual_cents': annualCents,
    'notes': notes.trim().isEmpty ? null : notes.trim(),
    'created_by': uid,
  };
  try {
    if (id == null || id.isEmpty) {
      await client.from('office_offers').insert(row);
    } else {
      await client.from('office_offers').update({
        'kind': row['kind'],
        'title': row['title'],
        'partner': row['partner'],
        'unit_cents': row['unit_cents'],
        'annual_cents': row['annual_cents'],
        'notes': row['notes'],
      }).eq('id', id);
    }
    return true;
  } on Object {
    return false;
  }
}

Future<void> hideOfficeOffer(String id) async {
  final client = trySupabaseClient();
  if (client == null || id.isEmpty) return;
  await client.from('office_offers').update({
    'deleted_at': DateTime.now().toUtc().toIso8601String(),
  }).eq('id', id);
}
