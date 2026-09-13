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

