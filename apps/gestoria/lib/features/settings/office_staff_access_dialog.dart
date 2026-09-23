import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/staff_access.dart';
import '../../core/theme/app_theme.dart';
import '../carpeta/bloque_template.dart';
import '../clientes/clientes_providers.dart';
import 'office_team_controller.dart';

/// Owner nastaví, které karty a bloky člen vidí. Ownera omezit nelze.
Future<void> showStaffAccessDialog(
  BuildContext context, {
  required OfficeMember member,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _StaffAccessDialog(member: member),
  );
}

class _StaffAccessDialog extends ConsumerStatefulWidget {
  const _StaffAccessDialog({required this.member});

  final OfficeMember member;

  @override
  ConsumerState<_StaffAccessDialog> createState() => _StaffAccessDialogState();
}

class _StaffAccessDialogState extends ConsumerState<_StaffAccessDialog> {
  var _loading = true;
  var _busy = false;
  var _scoped = false;
  final _clientes = <String>{};
  final _bloques = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final scope = await ref
        .read(officeTeamProvider.notifier)
        .loadScope(widget.member.profileId);
    if (!mounted) return;
    setState(() {
      _scoped = scope.scoped;
      _clientes
        ..clear()
        ..addAll(scope.clienteIds);
      _bloques
        ..clear()
        ..addAll(scope.bloqueKeys);
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(officeTeamProvider.notifier).saveScope(
            profileId: widget.member.profileId,
            scope: StaffAccessScope(
              scoped: _scoped,
              bloqueKeys: _bloques.toList(),
              clienteIds: _clientes.toList(),
            ),
          );
      if (mounted) Navigator.pop(context);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('settings.staffAccessError'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(clientesListProvider).valueOrNull ?? const [];
    final blockKeys = [
      for (final t in compraventaBloques)
        if (t.key != 'cliente_snapshot') t.key,
    ];
    return AlertDialog(
      title: Text('settings.staffAccess'.tr()),
      content: SizedBox(
        width: 480,
        height: 520,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('settings.staffScoped'.tr()),
                    subtitle: Text('settings.staffScopedHint'.tr()),
                    value: _scoped,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _scoped = v),
                  ),
                  if (_scoped) ...[
                    const SizedBox(height: 8),
                    Text(
                      'settings.staffClients'.tr(),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    for (final row in rows)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: _clientes.contains(row.id),
                        title: Text(row.nombre),
                        onChanged: _busy
                            ? null
                            : (on) => setState(() {
                                  if (on == true) {
                                    _clientes.add(row.id);
                                  } else {
                                    _clientes.remove(row.id);
                                  }
                                }),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'settings.staffBlocks'.tr(),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'settings.staffBlocksAll'.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.pencil,
                          ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final key in blockKeys)
                          FilterChip(
                            label: Text('blocks.$key'.tr()),
                            selected: _bloques.contains(key),
                            onSelected: _busy
                                ? null
                                : (on) => setState(() {
                                      if (on) {
                                        _bloques.add(key);
                                      } else {
                                        _bloques.remove(key);
                                      }
                                    }),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text('clients.cancel'.tr()),
        ),
        FilledButton(
          onPressed: _busy || _loading ? null : _save,
          child: Text('settings.staffAccessSave'.tr()),
        ),
      ],
    );
  }
}
