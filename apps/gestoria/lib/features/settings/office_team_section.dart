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
    return team.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, st) => Text('settings.loadError'.tr()),
      data: (members) {
        final people = AppSectionCard(
          title: 'settings.team'.tr(),
          hint: 'settings.teamHint'.tr(),
          child: members.isEmpty
              ? const SizedBox.shrink()
              : Column(
                  children: [
                    for (var i = 0; i < members.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      AppInsetRow(
                        title: members[i].fullName == null ||
                                members[i].fullName!.isEmpty
                            ? members[i].email
                            : members[i].fullName!,
                        subtitle: [
                          members[i].email,
                          'settings.role.${members[i].role}'.tr(),
                        ].join(' · '),
                        trailing: owner && members[i].role != 'owner'
                            ? IconButton(
                                tooltip: 'settings.removeMember'.tr(),
                                icon: const Icon(Icons.delete_outline),
                                onPressed: _busy
                                    ? null
                                    : () => ref
                                        .read(officeTeamProvider.notifier)
                                        .removeMember(members[i].id),
                              )
                            : null,
                      ),
                    ],
                  ],
                ),
        );
        final invite = !owner
            ? const SizedBox.shrink()
            : AppSectionCard(
                title: 'settings.inviteTitle'.tr(),
                hint: members.length >= officeTeamLimit
                    ? 'settings.teamFull'.tr()
                    : null,
                child: members.length >= officeTeamLimit
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final email = AppTextField(
                                controller: _email,
                                label: 'settings.inviteEmail'.tr(),
                                keyboardType: TextInputType.emailAddress,
                              );
                              final role = DropdownMenu<String>(
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
                              );
                              if (constraints.maxWidth < 520) {
                                return Column(
                                  children: [
                                    email,
                                    const SizedBox(height: 12),
                                    role,
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 3, child: email),
                                  const SizedBox(width: 12),
                                  Expanded(flex: 2, child: role),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton(
                              onPressed: _busy ? null : _invite,
                              child: Text('settings.invite'.tr()),
                            ),
                          ),
                        ],
                      ),
              );
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 900 || !owner) {
              return Column(
                children: [
                  people,
                  if (owner) ...[
                    const SizedBox(height: 16),
                    invite,
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: people),
                const SizedBox(width: 16),
                Expanded(child: invite),
              ],
            );
          },
        );
      },
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
      final kind = await ref.read(officeTeamProvider.notifier).invite(
            email: email,
            role: _role,
          );
      _email.clear();
      if (mounted) {
        switch (kind) {
          case OfficeInviteKind.existing:
            _toast('settings.memberAdded'.tr());
          case OfficeInviteKind.noEmail:
            _toast('settings.inviteNoEmail'.tr());
          case OfficeInviteKind.sent:
            _toast('settings.inviteSent'.tr());
        }
      }
    } on Object catch (e) {
      final msg = '$e';
      if (mounted) {
        if (msg.contains('team_full')) {
          _toast('settings.teamFull'.tr());
        } else if (msg.contains('already_member')) {
          _toast('settings.alreadyMember'.tr());
        } else if (msg.contains('already_registered')) {
          _toast('settings.alreadyRegistered'.tr());
        } else if (msg.contains('invite_redirect')) {
          _toast('settings.inviteRedirect'.tr());
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
