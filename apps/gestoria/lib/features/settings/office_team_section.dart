import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/auth/staff_role.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import 'office_team_controller.dart';

/// Owner zve gestor / asistente. Max 3 živé členství.
class OfficeTeamSection extends ConsumerStatefulWidget {
  const OfficeTeamSection({super.key});

  @override
  ConsumerState<OfficeTeamSection> createState() => _OfficeTeamSectionState();
}

class _OfficeTeamSectionState extends ConsumerState<OfficeTeamSection> {
  final _email = TextEditingController();
  var _role = 'gestor';
  var _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider).valueOrNull;
    final team = ref.watch(officeTeamProvider);
    final owner = auth != null && canInviteStaff(auth);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'settings.team'.tr(),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text('settings.teamHint'.tr()),
        const SizedBox(height: 8),
        team.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, st) => Text('settings.loadError'.tr()),
          data: (members) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in members)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: ListTile(
                        title: Text(
                          m.fullName == null || m.fullName!.isEmpty
                              ? m.email
                              : m.fullName!,
                        ),
                        subtitle: Text(
                          [
                            m.email,
                            'settings.role.${m.role}'.tr(),
                          ].join(' · '),
                        ),
                        trailing: owner && m.role != 'owner'
                            ? IconButton(
                                tooltip: 'settings.removeMember'.tr(),
                                icon: const Icon(Icons.delete_outline),
                                onPressed: _busy
                                    ? null
                                    : () => ref
                                        .read(officeTeamProvider.notifier)
                                        .removeMember(m.id),
                              )
                            : null,
                      ),
                    ),
                  ),
                if (owner && members.length < officeTeamLimit) ...[
                  AppTextField(
                    controller: _email,
                    label: 'settings.inviteEmail'.tr(),
                  ),
                  const SizedBox(height: 8),
                  DropdownMenu<String>(
                    initialSelection: _role,
                    label: Text('settings.roleLabel'.tr()),
                    expandedInsets: EdgeInsets.zero,
                    dropdownMenuEntries: [
                      DropdownMenuEntry(
                        value: 'gestor',
                        label: 'settings.role.gestor'.tr(),
                      ),
                      DropdownMenuEntry(
                        value: 'asistente',
                        label: 'settings.role.asistente'.tr(),
                      ),
                    ],
                    onSelected: (v) {
                      if (v == null) return;
                      setState(() => _role = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _busy ? null : _invite,
                    child: Text('settings.invite'.tr()),
                  ),
                ],
                if (owner && members.length >= officeTeamLimit)
                  Text('settings.teamFull'.tr()),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _invite() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _toast('settings.inviteEmail'.tr());
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(officeTeamProvider.notifier).invite(
            email: email,
            role: _role,
          );
      _email.clear();
      if (mounted) _toast('settings.inviteSent'.tr());
    } on Object catch (e) {
      final msg = '$e';
      if (mounted) {
        if (msg.contains('team_full')) {
          _toast('settings.teamFull'.tr());
        } else if (msg.contains('already_member')) {
          _toast('settings.alreadyMember'.tr());
        } else {
          _toast('settings.inviteError'.tr());
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
