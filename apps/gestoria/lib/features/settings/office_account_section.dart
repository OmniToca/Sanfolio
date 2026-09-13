import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/presentation/widgets/app_widgets.dart';

/// Účet přihlášeného člověka. Kancelář se nemění; AI sem nesahá.
class OfficeAccountSection extends ConsumerStatefulWidget {
  const OfficeAccountSection({super.key});

  @override
  ConsumerState<OfficeAccountSection> createState() =>
      _OfficeAccountSectionState();
}

class _OfficeAccountSectionState extends ConsumerState<OfficeAccountSection> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    final issue = passwordChangeIssue(
      current: _current.text,
      next: _next.text,
      confirm: _confirm.text,
    );
    if (issue != PasswordChangeIssue.none) {
      setState(() => _error = passwordChangeI18nKey(issue));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      if (!mounted) return;
      _current.clear();
      _next.clear();
      _confirm.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('auth.passwordUpdated'.tr())),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = authErrorI18nKey(e.message));
    } on Object {
      if (mounted) setState(() => _error = 'auth.updatePasswordError');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final auth = ref.read(authControllerProvider.notifier);
    final snap = ref.read(authControllerProvider).valueOrNull;
    setState(() => _busy = true);
    try {
      if (snap?.impersonating == true) {
        await auth.endImpersonationAndReturnToSupport();
      } else {
        await auth.signOut();
      }
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('auth.signOutError'.tr())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(authControllerProvider).valueOrNull;
    final email = snap?.profile?.email.trim() ?? '';
    final impersonating = snap?.impersonating == true;
    return AppSectionCard(
      title: 'settings.accountTitle'.tr(),
      hint: impersonating
          ? 'settings.accountImpersonationHint'.tr()
          : 'settings.accountHint'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (email.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                email,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          if (!impersonating) ...[
            TextField(
              controller: _current,
              obscureText: true,
              enabled: !_busy,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'auth.currentPassword'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _next,
              obscureText: true,
              enabled: !_busy,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'auth.newPassword'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              enabled: !_busy,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'auth.confirmPassword'.tr(),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _savePassword(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!.tr(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _busy ? null : _savePassword,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('auth.changePassword'.tr()),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : _leave,
              child: Text(
                impersonating
                    ? 'impersonation.end'.tr()
                    : 'auth.signOut'.tr(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
