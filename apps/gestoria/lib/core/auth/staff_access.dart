/// Rozsah člena kanceláře. Owner a nescopovaný člen vidí vše.
class StaffAccessScope {
  const StaffAccessScope({
    this.scoped = false,
    this.bloqueKeys = const [],
    this.clienteIds = const [],
  });

  final bool scoped;
  final List<String> bloqueKeys;
  final List<String> clienteIds;

  static const open = StaffAccessScope();
}

/// Identita na desce zůstane, i když má jen vodu a elektřinu.
bool staffMaySeeBloque({
  required bool isOwner,
  required StaffAccessScope scope,
  required String templateKey,
}) {
  if (isOwner || !scope.scoped) return true;
  if (templateKey == 'cliente_snapshot') return true;
  if (scope.bloqueKeys.isEmpty) return true;
  return scope.bloqueKeys.contains(templateKey);
}

bool staffMaySeeCliente({
  required bool isOwner,
  required StaffAccessScope scope,
  required String clienteId,
}) {
  if (isOwner || !scope.scoped) return true;
  return scope.clienteIds.contains(clienteId);
}

/// Novou kartu a import CSV zakládá owner a nescopovaný člen.
bool staffMayCreateClientes({
  required bool isOwner,
  required StaffAccessScope scope,
}) {
  return isOwner || !scope.scoped;
}
