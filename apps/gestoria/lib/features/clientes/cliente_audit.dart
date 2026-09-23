import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/auth/staff_role.dart';

/// Pole karty, která má smysl ukázat ve stopě (ne UUID / timestamps).
const auditClienteFieldI18n = <String, String>{
  'nombre': 'clients.name',
  'email': 'fields.email',
  'tel': 'fields.tel',
  'iban': 'fields.iban',
  'notas': 'clients.notes',
  'locale': 'clients.locale',
  'status': 'clients.status',
  'nie': 'fields.nie',
};

/// Řádek stopy na kartě. Insert jde z RPC/triggeru, ne z Flutteru.
class ClienteAuditEvent {
  const ClienteAuditEvent({
    required this.id,
    required this.createdAt,
    required this.action,
    this.actorLabel,
    this.impersonating = false,
    this.detail = const {},
  });

  final String id;
  final DateTime createdAt;
  final String action;
  final String? actorLabel;
  final bool impersonating;
  final Map<String, dynamic> detail;

  String? get surface {
    final v = '${detail['surface'] ?? ''}'.trim();
    return v.isEmpty ? null : v;
  }

  String? get documentTipo {
    final v = '${detail['tipo'] ?? ''}'.trim();
    return v.isEmpty ? null : v;
  }

  String? get documentName {
    final v = '${detail['original_name'] ?? ''}'.trim();
    return v.isEmpty ? null : v;
  }

  String? get asunto {
    final v = '${detail['asunto'] ?? ''}'.trim();
    return v.isEmpty ? null : v;
  }

  String? get contactNombre {
    final v = '${detail['nombre'] ?? ''}'.trim();
    return v.isEmpty ? null : v;
  }

  String? get contactRelacion {
    final v = '${detail['relacion'] ?? ''}'.trim();
    return v.isEmpty ? null : v;
  }

  List<String> get changedFields {
    final raw = detail['changed'];
    if (raw is! List) return const [];
    return [
      for (final x in raw)
        if ('$x'.trim().isNotEmpty) '$x'.trim(),
    ];
  }

  /// Karta vs. složka vs. dokument — bez toho je „otevření“ prázdné slovo.
  String get actionI18nKey {
    if (action == 'clientes.open' && surface == 'carpeta') {
      return 'audit.action.clientes.openCarpeta';
    }
    return 'audit.action.$action';
  }
}

Map<String, dynamic> _asStringKeyedMap(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final e in raw.entries) '${e.key}': e.value,
  };
}

/// Člen kanceláře vidí, kdo kartu otevřel / změnil / odeslal. Scoped jen svoje karty.
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
        detail: _asStringKeyedMap(raw['detail']),
      ),
    );
  }
  return out;
});

Future<void> _auditOpen({
  required String entityTable,
  required String entityId,
  required String tenantId,
  Map<String, Object?>? after,
}) async {
  final client = trySupabaseClient();
  if (client == null) return;
  try {
    await client.rpc(
      'audit_open',
      params: {
        'p_entity_table': entityTable,
        'p_entity_id': entityId,
        'p_tenant_id': tenantId,
        if (after != null) 'p_after': after,
      },
    );
  } on Object {
    // Práce na kartě nesmí spadnout kvůli stopě.
  }
}

/// LOPDGDD: otevření karty musí zanechat stopu. Selhání nesmí zavřít kartu.
Future<void> auditClienteOpen({
  required String clienteId,
  required String tenantId,
  String surface = 'card',
}) {
  return _auditOpen(
    entityTable: 'clientes',
    entityId: clienteId,
    tenantId: tenantId,
    after: {'surface': surface},
  );
}

/// Kdo otevřel který sken. Bez názvu je „otevření“ k ničemu.
Future<void> auditDocumentoOpen({
  required String documentId,
  required String tenantId,
  required String tipo,
  required String originalName,
}) {
  return _auditOpen(
    entityTable: 'documentos',
    entityId: documentId,
    tenantId: tenantId,
    after: {
      'tipo': tipo,
      if (originalName.trim().isNotEmpty) 'original_name': originalName.trim(),
    },
  );
}
