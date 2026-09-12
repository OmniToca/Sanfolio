import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

/// Filtr seznamu: neaktivní schovat, nesmazat. Smazané jen owner.
enum ClientesListFilter { activo, inactivo, deleted }

/// Owner nebo impersonace Supportu smí obnovit soft-delete.
bool canRestoreDeleted(AuthSnapshot snap) {
  if (snap.impersonating) return true;
  final tid = snap.currentTenantId;
  if (tid == null) return false;
  return snap.memberships.any((m) => m.tenantId == tid && m.role == 'owner');
}

/// Řádek seznamu. Název a NIE z DB, ne z i18n.
class ClienteRow {
  const ClienteRow({
    required this.id,
    required this.nombre,
    required this.status,
    this.nie,
    this.email,
    this.tel,
    this.deleted = false,
  });

  final String id;
  final String nombre;
  final String status;
  final String? nie;
  final String? email;
  final String? tel;
  final bool deleted;

  String get subtitle {
    final bits = <String>[
      if (nie != null && nie!.isNotEmpty) nie!,
      if (email != null && email!.isNotEmpty) email!,
      if (tel != null && tel!.isNotEmpty) tel!,
    ];
    return bits.join(' · ');
  }
}

final clientesQueryProvider = StateProvider<String>((ref) => '');
final clientesFilterProvider =
    StateProvider<ClientesListFilter>((ref) => ClientesListFilter.activo);

final clientesListProvider = FutureProvider<List<ClienteRow>>((ref) async {
  ref.watch(authControllerProvider);
  final auth = await ref.watch(authControllerProvider.future);
  final tenantId = auth.currentTenantId;
  final client = trySupabaseClient();
  if (tenantId == null || client == null) return [];

  final filter = ref.watch(clientesFilterProvider);
  final q = ref.watch(clientesQueryProvider).trim();
  final orderedIds = <String>[];
  final allowDeleted = canRestoreDeleted(auth);
  final effective = (!allowDeleted && filter == ClientesListFilter.deleted)
      ? ClientesListFilter.activo
      : filter;
  // search_clients vynechává smazané — u koše jen seznam schovaných.
  if (q.isNotEmpty && effective != ClientesListFilter.deleted) {
    final hits = await client.rpc(
      'search_clients',
      params: {'p_q': q, 'p_limit': 40},
    );
    if (hits is List) {
      for (final raw in hits) {
        if (raw is Map && raw['cliente_id'] != null) {
          final id = '${raw['cliente_id']}';
          if (!orderedIds.contains(id)) orderedIds.add(id);
        }
      }
    }
    if (orderedIds.isEmpty) return [];
  }

  var query = client
      .from('clientes')
      .select(
        'id, nombre, apellidos, email, tel, status, deleted_at, '
        'client_identifiers(kind, value_raw, deleted_at)',
      )
      .eq('tenant_id', tenantId);
  switch (effective) {
    case ClientesListFilter.activo:
      query = query.isFilter('deleted_at', null).eq('status', 'activo');
    case ClientesListFilter.inactivo:
      query = query.isFilter('deleted_at', null).eq('status', 'inactivo');
    case ClientesListFilter.deleted:
      query = query.not('deleted_at', 'is', null);
  }
  if (orderedIds.isNotEmpty) {
    query = query.inFilter('id', orderedIds);
  }
  final rows = await query.order('updated_at', ascending: false);
  final out = <ClienteRow>[];
  for (final raw in rows as List) {
    if (raw is! Map) continue;
    out.add(_rowFrom(raw));
  }
  if (orderedIds.isNotEmpty) {
    out.sort((a, b) {
      return orderedIds.indexOf(a.id).compareTo(orderedIds.indexOf(b.id));
    });
  }
  return out;
});

Future<String> openCarpetaCompraventa({
  required String tenantId,
  required String nombre,
  String? email,
  String? tel,
  String? nie,
}) async {
  final client = trySupabaseClient();
  if (client == null) {
    throw StateError('not configured');
  }
  final id = await client.rpc(
    'open_carpeta_compraventa',
    params: {
      'p_tenant_id': tenantId,
      'p_nombre': nombre,
      'p_email': email,
      'p_tel': tel,
      'p_nie': nie,
    },
  );
  return '$id';
}

Future<String> addInmuebleCompraventa({
  required String clienteId,
  required String direccion,
}) async {
  final client = trySupabaseClient();
  if (client == null) throw StateError('not configured');
  final id = await client.rpc(
    'add_inmueble_compraventa',
    params: {
      'p_cliente_id': clienteId,
      'p_direccion': direccion,
    },
  );
  return '$id';
}

ClienteRow _rowFrom(Map<dynamic, dynamic> raw) {
  final nombre = [
    '${raw['nombre'] ?? ''}'.trim(),
    '${raw['apellidos'] ?? ''}'.trim(),
  ].where((s) => s.isNotEmpty).join(' ');
  String? nie;
  final ids = raw['client_identifiers'];
  if (ids is List) {
    for (final item in ids) {
      if (item is! Map) continue;
      if (item['deleted_at'] != null) continue;
      nie = '${item['value_raw'] ?? ''}'.trim();
      if (nie.isNotEmpty) break;
    }
  }
  return ClienteRow(
    id: '${raw['id']}',
    nombre: nombre,
    status: '${raw['status'] ?? 'activo'}',
    nie: nie,
    email: '${raw['email'] ?? ''}'.trim().isEmpty
        ? null
        : '${raw['email']}'.trim(),
    tel: '${raw['tel'] ?? ''}'.trim().isEmpty ? null : '${raw['tel']}'.trim(),
    deleted: raw['deleted_at'] != null,
  );
}
