import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/identity/nie_persist.dart';
import '../settings/office_settings_controller.dart';
import 'poder_glance.dart';

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
    this.coOwnerNombre,
    this.coOwnerAddress,
    this.poder = PoderGlance.missing,
  });

  final String id;
  final String nombre;
  final String status;
  final String? nie;
  final String? email;
  final String? tel;
  final bool deleted;
  final String? coOwnerNombre;
  final String? coOwnerAddress;
  final PoderGlance poder;

  bool get isCoOwnerOnly =>
      (coOwnerNombre ?? '').isNotEmpty || (coOwnerAddress ?? '').isNotEmpty;

  String get subtitle {
    final bits = <String>[
      if (nie != null && nie!.isNotEmpty) nie!,
      if (email != null && email!.isNotEmpty) email!,
      if (tel != null && tel!.isNotEmpty) tel!,
    ];
    return bits.join(' · ');
  }

  ClienteRow withCoOwner({String? nombre, String? address}) {
    return ClienteRow(
      id: id,
      nombre: this.nombre,
      status: status,
      nie: nie,
      email: email,
      tel: tel,
      deleted: deleted,
      coOwnerNombre: nombre,
      coOwnerAddress: address,
      poder: poder,
    );
  }

  ClienteRow withPoder(PoderGlance next) {
    return ClienteRow(
      id: id,
      nombre: nombre,
      status: status,
      nie: nie,
      email: email,
      tel: tel,
      deleted: deleted,
      coOwnerNombre: coOwnerNombre,
      coOwnerAddress: coOwnerAddress,
      poder: next,
    );
  }
}

final clientesQueryProvider = StateProvider<String>((ref) => '');
final clientesFilterProvider = StateProvider<ClientesListFilter>(
  (ref) => ClientesListFilter.activo,
);

/// Filtr poderu nad už načteným seznamem. Není to druhá evidence.
enum ClientesPoderFilter { all, withCopy, missing }

final clientesPoderFilterProvider = StateProvider<ClientesPoderFilter>(
  (ref) => ClientesPoderFilter.all,
);

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
    try {
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
    } on Object {
      // RPC nesmí shodit celou desku. Doplní se ilike níž.
    }
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
  } else if (q.isNotEmpty && effective != ClientesListFilter.deleted) {
    final safe = q.replaceAll(RegExp(r'[%_,.()"]'), ' ').trim();
    if (safe.isEmpty) return [];
    query = query.or(
      'nombre.ilike.%$safe%,apellidos.ilike.%$safe%,email.ilike.%$safe%,tel.ilike.%$safe%',
    );
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
  final hinted = await _withCoOwnerHints(
    client: client,
    tenantId: tenantId,
    rows: out,
  );
  return _withPoderGlances(
    client: client,
    tenantId: tenantId,
    warnDays: ref.watch(officeSettingsProvider).valueOrNull?.poderWarnDays ?? 60,
    rows: hinted,
  );
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
    params: {'p_cliente_id': clienteId, 'p_direccion': direccion},
  );
  return '$id';
}

/// Složka má vlastní inmueble. Spoluvlastník jen titular jinde — ať seznam není druhá prázdná deska.
Future<List<ClienteRow>> _withCoOwnerHints({
  required dynamic client,
  required String tenantId,
  required List<ClienteRow> rows,
}) async {
  if (rows.isEmpty) return rows;
  try {
    final ids = [for (final r in rows) r.id];
    final owned = <String>{};
    final ownRows = await client
        .from('inmuebles')
        .select('cliente_id')
        .eq('tenant_id', tenantId)
        .inFilter('cliente_id', ids)
        .isFilter('deleted_at', null);
    if (ownRows is List) {
      for (final raw in ownRows) {
        if (raw is Map) {
          final id = '${raw['cliente_id'] ?? ''}'.trim();
          if (id.isNotEmpty) owned.add(id);
        }
      }
    }
    final titRows = await client
        .from('inmueble_titulares')
        .select('cliente_id, inmueble_id')
        .eq('tenant_id', tenantId)
        .eq('lado', 'comprador')
        .inFilter('cliente_id', ids)
        .isFilter('deleted_at', null);
    final clienteToInm = <String, String>{};
    final inmIds = <String>[];
    if (titRows is List) {
      for (final raw in titRows) {
        if (raw is! Map) continue;
        final cid = '${raw['cliente_id'] ?? ''}'.trim();
        final iid = '${raw['inmueble_id'] ?? ''}'.trim();
        if (cid.isEmpty || iid.isEmpty || owned.contains(cid)) continue;
        if (clienteToInm.containsKey(cid)) continue;
        clienteToInm[cid] = iid;
        inmIds.add(iid);
      }
    }
    if (inmIds.isEmpty) return rows;
    final inmRows = await client
        .from('inmuebles')
        .select('id, direccion, cliente_id')
        .inFilter('id', inmIds)
        .isFilter('deleted_at', null);
    final inmById = <String, Map>{};
    final ownerIds = <String>[];
    if (inmRows is List) {
      for (final raw in inmRows) {
        if (raw is! Map) continue;
        inmById['${raw['id']}'] = raw;
        final oid = '${raw['cliente_id'] ?? ''}'.trim();
        if (oid.isNotEmpty) ownerIds.add(oid);
      }
    }
    final ownerName = <String, String>{};
    if (ownerIds.isNotEmpty) {
      final people = await client
          .from('clientes')
          .select('id, nombre, apellidos')
          .inFilter('id', ownerIds);
      if (people is List) {
        for (final raw in people) {
          if (raw is! Map) continue;
          ownerName['${raw['id']}'] = [
            '${raw['nombre'] ?? ''}'.trim(),
            '${raw['apellidos'] ?? ''}'.trim(),
          ].where((s) => s.isNotEmpty).join(' ');
        }
      }
    }
    return [
      for (final row in rows)
        () {
          final iid = clienteToInm[row.id];
          if (iid == null) return row;
          final inm = inmById[iid];
          if (inm == null) return row;
          final oid = '${inm['cliente_id'] ?? ''}'.trim();
          final addr = '${inm['direccion'] ?? ''}'.trim();
          final name = ownerName[oid] ?? '';
          if (name.isEmpty && addr.isEmpty) return row;
          return row.withCoOwner(
            nombre: name.isEmpty ? null : name,
            address: addr.isEmpty ? null : addr,
          );
        }(),
    ];
  } on Object {
    return rows;
  }
}

Future<List<ClienteRow>> _withPoderGlances({
  required dynamic client,
  required String tenantId,
  required int warnDays,
  required List<ClienteRow> rows,
}) async {
  if (rows.isEmpty) return rows;
  try {
    final hits = await client.rpc(
      'cliente_poder_glance',
      params: {
        'p_tenant_id': tenantId,
        'p_cliente_ids': [for (final r in rows) r.id],
      },
    );
    if (hits is! List) return rows;
    final today = DateTime.now();
    final byId = <String, PoderGlance>{};
    for (final raw in hits) {
      if (raw is! Map) continue;
      final id = '${raw['cliente_id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      byId[id] = poderGlanceFromRpc(
        raw: raw,
        today: today,
        warnDays: warnDays,
      );
    }
    return [
      for (final row in rows) row.withPoder(byId[row.id] ?? PoderGlance.missing),
    ];
  } on Object {
    return rows;
  }
}

ClienteRow _rowFrom(Map<dynamic, dynamic> raw) {
  final nombre = [
    '${raw['nombre'] ?? ''}'.trim(),
    '${raw['apellidos'] ?? ''}'.trim(),
  ].where((s) => s.isNotEmpty).join(' ');
  final nie = preferredFiscalRawFromRows(raw['client_identifiers']);
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
