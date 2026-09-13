/// Řádek z `client_identifiers` pro výběr NIE na kartě / desce.
class IdentifierRaw {
  const IdentifierRaw({required this.kind, required this.valueRaw});

  final String kind;
  final String valueRaw;
}

/// NIE pole ukáže fiskální ID, ne pas. Preferuje `nie`, pak dni/nif.
String? preferredFiscalRaw(Iterable<IdentifierRaw> rows) {
  String? firstFiscal;
  for (final row in rows) {
    final v = row.valueRaw.trim();
    if (v.isEmpty) continue;
    if (row.kind == 'nie') return v;
    if (firstFiscal == null &&
        (row.kind == 'dni' || row.kind == 'nif')) {
      firstFiscal = v;
    }
  }
  return firstFiscal;
}

/// Parsuje `client_identifiers` z PostgREST. Přeskočí smazané.
String? preferredFiscalRawFromRows(Object? raw) {
  if (raw is! List) return null;
  return preferredFiscalRaw([
    for (final item in raw)
      if (item is Map && item['deleted_at'] == null)
        IdentifierRaw(
          kind: '${item['kind'] ?? ''}',
          valueRaw: '${item['value_raw'] ?? ''}',
        ),
  ]);
}

/// NIE / DNI / NIF z normalizovaného čísla.
String identifierKindFromNormalized(String normalized) {
  final n = normalized.trim().toUpperCase();
  if (RegExp(r'^[XYZ][0-9*]{7}[A-Z]$').hasMatch(n)) return 'nie';
  if (RegExp(r'^[0-9*]{8}[A-Z]$').hasMatch(n)) return 'dni';
  if (RegExp(r'^[A-HJ-NP-SUVW][0-9*]{7}[0-9A-J]$').hasMatch(n)) {
    return 'nif';
  }
  return 'other';
}

/// Živý identifikátor na kartě. Persist NIE sahá jen na `kind=nie`, ne na pas.
class LiveIdentifier {
  const LiveIdentifier({
    required this.id,
    required this.kind,
    required this.valueNormalized,
    this.clienteId = '',
    this.valueRaw = '',
  });

  final String id;
  final String kind;
  final String valueNormalized;
  final String clienteId;
  final String valueRaw;
}

enum NiePersistOp { none, insert, update, softDeleteNie }

/// Co zapsat do `client_identifiers`. Prázdné NIE nemaže pas/DNI.
class NiePersistPlan {
  const NiePersistPlan({
    required this.op,
    this.targetId,
    this.normalized,
    this.kind,
  });

  final NiePersistOp op;
  final String? targetId;
  final String? normalized;
  final String? kind;
}

bool _isFiscalKind(String kind) =>
    kind == 'nie' || kind == 'dni' || kind == 'nif';

/// Stejné číslo nesmí držet dvě karty (nie vs dni).
bool fiscalIdConflicts({
  required String normalized,
  required String clienteId,
  required List<LiveIdentifier> liveInTenant,
}) {
  if (normalized.isEmpty || normalized.contains('*')) return false;
  for (final row in liveInTenant) {
    if (row.clienteId == clienteId) continue;
    if (!_isFiscalKind(row.kind)) continue;
    if (row.valueNormalized == normalized) return true;
  }
  return false;
}

NiePersistPlan planNiePersist({
  required String nieNormalized,
  required List<LiveIdentifier> liveOnCliente,
}) {
  LiveIdentifier? nieRow;
  LiveIdentifier? sameValue;
  for (final row in liveOnCliente) {
    if (row.kind == 'nie') nieRow ??= row;
    if (nieNormalized.isNotEmpty &&
        _isFiscalKind(row.kind) &&
        row.valueNormalized == nieNormalized) {
      sameValue ??= row;
    }
  }
  if (nieNormalized.isEmpty) {
    if (nieRow != null) {
      return NiePersistPlan(
        op: NiePersistOp.softDeleteNie,
        targetId: nieRow.id,
      );
    }
    return const NiePersistPlan(op: NiePersistOp.none);
  }
  final kind = identifierKindFromNormalized(nieNormalized);
  if (sameValue != null) {
    return NiePersistPlan(
      op: NiePersistOp.update,
      targetId: sameValue.id,
      normalized: nieNormalized,
      kind: kind,
    );
  }
  if (nieRow != null) {
    return NiePersistPlan(
      op: NiePersistOp.update,
      targetId: nieRow.id,
      normalized: nieNormalized,
      kind: kind,
    );
  }
  return NiePersistPlan(
    op: NiePersistOp.insert,
    normalized: nieNormalized,
    kind: kind,
  );
}

/// Unique Postgres / PostgREST (dvě karty, stejné číslo).
bool looksLikeUniqueConstraint(Object error) {
  final s = '$error'.toLowerCase();
  return s.contains('23505') ||
      s.contains('duplicate key') ||
      s.contains('uq_client_identifiers');
}

/// Po konfliktu nesmí v JSON desky zůstat cizí NIE.
String nieFieldAfterConflict({
  required bool conflict,
  required String typedRaw,
  required Iterable<LiveIdentifier> liveOnCliente,
}) {
  if (!conflict) return typedRaw;
  return preferredFiscalRaw([
        for (final row in liveOnCliente)
          IdentifierRaw(
            kind: row.kind,
            valueRaw: row.valueRaw.isNotEmpty
                ? row.valueRaw
                : row.valueNormalized,
          ),
      ]) ??
      '';
}

/// Fokus drží tužku. NIE po konfliktu se musí vrátit i když pole má fokus.
bool syncDeskFieldFromParent({
  required String fieldKey,
  required bool focused,
}) =>
    !focused || fieldKey == 'fields.nie';

/// Identifikátory a persona přepíší JSON desky. Prázdné NIE smaže vepsané číslo.
void overlayClienteSnapshot({
  required Map<String, String> desk,
  required Map<String, String> live,
}) {
  for (final e in live.entries) {
    if (e.key == 'fields.nie' || e.value.isNotEmpty) {
      desk[e.key] = e.value;
    }
  }
}

/// Konflikt unique vs. plán zápisu. Bez I/O.
NieSaveDecision decideNieSave({
  required String nieRaw,
  required String nieNormalized,
  required String clienteId,
  required List<LiveIdentifier> liveOnCliente,
  required List<LiveIdentifier> liveInTenant,
}) {
  final typed = nieRaw.trim();
  if (nieNormalized.isNotEmpty &&
      fiscalIdConflicts(
        normalized: nieNormalized,
        clienteId: clienteId,
        liveInTenant: liveInTenant,
      )) {
    return NieSaveDecision(
      conflict: true,
      plan: const NiePersistPlan(op: NiePersistOp.none),
      keepNie: nieFieldAfterConflict(
        conflict: true,
        typedRaw: typed,
        liveOnCliente: liveOnCliente,
      ),
      typedNie: typed,
    );
  }
  return NieSaveDecision(
    conflict: false,
    plan: planNiePersist(
      nieNormalized: nieNormalized,
      liveOnCliente: liveOnCliente,
    ),
    keepNie: typed,
    typedNie: typed,
  );
}

class NieSaveDecision {
  const NieSaveDecision({
    required this.conflict,
    required this.plan,
    required this.keepNie,
    required this.typedNie,
  });

  final bool conflict;
  final NiePersistPlan plan;
  final String keepNie;
  final String typedNie;
}

/// Zápis `client_identifiers`. Stejná cesta na desce i na kartě.
Future<({bool conflict, String keepNie, String typedNie})> persistClienteNie({
  required dynamic client,
  required String tenantId,
  required String clienteId,
  required String nieRaw,
}) async {
  const ok = (conflict: false, keepNie: '', typedNie: '');
  final nie = nieRaw.trim();
  final rawIds = await client
      .from('client_identifiers')
      .select('id, kind, value_normalized, value_raw')
      .eq('cliente_id', clienteId)
      .isFilter('deleted_at', null);
  final live = <LiveIdentifier>[
    for (final row in rawIds as List)
      LiveIdentifier(
        id: '${row['id']}',
        kind: '${row['kind']}',
        valueNormalized: '${row['value_normalized']}',
        valueRaw: '${row['value_raw'] ?? ''}',
        clienteId: clienteId,
      ),
  ];
  var normalized = '';
  if (nie.isNotEmpty) {
    try {
      final n = await client.rpc('normalize_id', params: {'raw': nie});
      if (n != null) normalized = '$n';
    } on Object {
      normalized = nie.toUpperCase().replaceAll(RegExp(r'[\s\-\./]'), '');
    }
  }
  var tenantLive = const <LiveIdentifier>[];
  if (normalized.isNotEmpty) {
    final others = await client
        .from('client_identifiers')
        .select('id, kind, value_normalized, cliente_id')
        .eq('tenant_id', tenantId)
        .eq('value_normalized', normalized)
        .isFilter('deleted_at', null);
    tenantLive = [
      for (final row in others as List)
        LiveIdentifier(
          id: '${row['id']}',
          kind: '${row['kind']}',
          valueNormalized: '${row['value_normalized']}',
          clienteId: '${row['cliente_id']}',
        ),
    ];
  }
  final decision = decideNieSave(
    nieRaw: nie,
    nieNormalized: normalized,
    clienteId: clienteId,
    liveOnCliente: live,
    liveInTenant: tenantLive,
  );
  if (decision.conflict) {
    return (
      conflict: true,
      keepNie: decision.keepNie,
      typedNie: decision.typedNie,
    );
  }
  try {
    await applyNiePersistPlan(
      client: client,
      tenantId: tenantId,
      clienteId: clienteId,
      nieRaw: nie,
      plan: decision.plan,
    );
    return ok;
  } on Object catch (e) {
    if (looksLikeUniqueConstraint(e)) {
      return (
        conflict: true,
        keepNie: nieFieldAfterConflict(
          conflict: true,
          typedRaw: nie,
          liveOnCliente: live,
        ),
        typedNie: nie,
      );
    }
    rethrow;
  }
}

Future<void> applyNiePersistPlan({
  required dynamic client,
  required String tenantId,
  required String clienteId,
  required String nieRaw,
  required NiePersistPlan plan,
}) async {
  switch (plan.op) {
    case NiePersistOp.none:
      return;
    case NiePersistOp.softDeleteNie:
      await client.from('client_identifiers').update({
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', plan.targetId!);
      return;
    case NiePersistOp.update:
      await client.from('client_identifiers').update({
        'value_raw': nieRaw,
        'value_normalized': plan.normalized,
        'kind': plan.kind,
      }).eq('id', plan.targetId!);
      return;
    case NiePersistOp.insert:
      await client.from('client_identifiers').insert({
        'tenant_id': tenantId,
        'cliente_id': clienteId,
        'kind': plan.kind,
        'value_raw': nieRaw,
        'value_normalized': plan.normalized,
        'checksum': 'unknown',
      });
  }
}

