import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/identity/nie_persist.dart';
import '../../core/presentation/widgets/app_widgets.dart';

/// Klient na fakturu. Pole jdou do formuláře a jdou přepsat ručně.
class FacturaClientePick {
  const FacturaClientePick({
    required this.id,
    required this.nombre,
    this.nie,
    this.email,
    this.direccion,
    this.tel,
  });

  final String id;
  final String nombre;
  final String? nie;
  final String? email;
  final String? direccion;
  final String? tel;

  String get subtitle {
    final bits = [
      if ((nie ?? '').isNotEmpty) nie!,
      if ((email ?? '').isNotEmpty) email!,
    ];
    return bits.join(' · ');
  }
}

/// Seznam aktivních karet pro výběr příjemce. UI nevolá Supabase samo.
Future<List<FacturaClientePick>> fetchFacturaClientes(String tenantId) async {
  final client = trySupabaseClient();
  if (client == null) return const [];
  final rows = await client
      .from('clientes')
      .select(
        'id, nombre, email, tel, direccion, '
        'client_identifiers(kind, value_raw, deleted_at)',
      )
      .eq('tenant_id', tenantId)
      .isFilter('deleted_at', null)
      .eq('status', 'activo')
      .order('nombre')
      .limit(80);
  final out = <FacturaClientePick>[];
  for (final raw in rows) {
    final nombre = '${raw['nombre'] ?? ''}'.trim();
    if (nombre.isEmpty) continue;
    out.add(
      FacturaClientePick(
        id: '${raw['id']}',
        nombre: nombre,
        nie: preferredFiscalRawFromRows(raw['client_identifiers']),
        email: _opt(raw['email']),
        direccion: _opt(raw['direccion']),
        tel: _opt(raw['tel']),
      ),
    );
  }
  return out;
}

String? _opt(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

class FacturaClientePickDialog extends ConsumerStatefulWidget {
  const FacturaClientePickDialog({super.key});

  @override
  ConsumerState<FacturaClientePickDialog> createState() =>
      _FacturaClientePickDialogState();
}

class _FacturaClientePickDialogState
    extends ConsumerState<FacturaClientePickDialog> {
  final _q = TextEditingController();
  List<FacturaClientePick> _all = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    if (tenantId == null) {
      setState(() => _loading = false);
      return;
    }
    final rows = await fetchFacturaClientes(tenantId);
    if (!mounted) return;
    setState(() {
      _all = rows;
      _loading = false;
    });
  }

  List<FacturaClientePick> get _filtered {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return [
      for (final r in _all)
        if (r.nombre.toLowerCase().contains(q) ||
            (r.nie ?? '').toLowerCase().contains(q) ||
            (r.email ?? '').toLowerCase().contains(q))
          r,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return AlertDialog(
      title: Text('facturacion.pickCliente'.tr()),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              label: 'clients.searchHint'.tr(),
              controller: _q,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              )
            else
              SizedBox(
                height: 280,
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    return ListTile(
                      title: Text(r.nombre),
                      subtitle: r.subtitle.isEmpty ? null : Text(r.subtitle),
                      onTap: () => Navigator.pop(context, r),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('clients.cancel'.tr()),
        ),
      ],
    );
  }
}
