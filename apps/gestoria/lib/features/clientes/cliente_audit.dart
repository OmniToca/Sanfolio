import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/auth/staff_role.dart';

/// Řádek stopy na kartě. Insert jde z RPC/triggeru, ne z Flutteru.
class ClienteAuditEvent {
  const ClienteAuditEvent({
    required this.id,
    required this.createdAt,
    required this.action,
    this.actorLabel,
    this.impersonating = false,
  });

  final String id;
  final DateTime createdAt;
  final String action;
  final String? actorLabel;
  final bool impersonating;

  String get actionI18nKey => 'audit.action.$action';
}

/// Owner (a Support v impersonaci) vidí, kdo kartu otevřel / změnil / odeslal.
final clienteAuditProvider =
    FutureProvider.family<List<ClienteAuditEvent>, String>((ref, clienteId) async {
  ref.watch(authControllerProvider);
  final client = trySupabaseClient();
  final auth = ref.read(authControllerProvider).valueOrNull;
  if (client == null || auth == null || !canViewClienteAudit(auth)) {
    return const [];
  }
  final rows = await client.rpc(
    'cliente_audit_log',
    params: {'p_cliente_id': clienteId},
  );
  if (rows is! List) return const [];
  final out = <ClienteAuditEvent>[];
  for (final raw in rows) {
    if (raw is! Map) continue;
    final created = DateTime.tryParse('${raw['created_at'] ?? ''}');
    if (created == null) continue;
    final name = '${raw['actor_name'] ?? ''}'.trim();
    final email = '${raw['actor_email'] ?? ''}'.trim();
    out.add(
      ClienteAuditEvent(
        id: '${raw['id']}',
        createdAt: created.toUtc(),
        action: '${raw['action'] ?? ''}',
        actorLabel: name.isNotEmpty
            ? name
            : (email.isNotEmpty ? email : null),
        impersonating: raw['impersonating'] == true,
      ),
    );
  }
  return out;
});

/// LOPDGDD: otevření karty musí zanechat stopu. Selhání nesmí zavřít kartu.
Future<void> auditClienteOpen({
  required String clienteId,
  required String tenantId,
}) async {
  final client = trySupabaseClient();
  if (client == null) return;
  try {
    await client.rpc(
      'audit_open',
      params: {
        'p_entity_table': 'clientes',
        'p_entity_id': clienteId,
        'p_tenant_id': tenantId,
      },
    );
  } on Object {
    // Karta je zdroj pravdy pro práci; audit se doplní příště.
  }
}
