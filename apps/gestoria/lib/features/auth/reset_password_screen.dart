import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

/// Veřejná routa. Nové heslo jen ze session `passwordRecovery` (odkaz v e-mailu).
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pass = _password.text;
    if (pass.length < 8) {
      setState(() => _error = 'auth.passwordTooShort');
      return;
    }
    if (pass != _confirm.text) {
      setState(() => _error = 'auth.passwordMismatch');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).updatePassword(pass);
    } on Object {
      if (mounted) setState(() => _error = 'auth.updatePasswordError');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestLink() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'auth.emailRequired');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .requestPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('auth.resetSent'.tr())),
      );
    } on Object {
      if (mounted) setState(() => _error = 'auth.resetError');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final recovery = auth.valueOrNull?.passwordRecovery == true;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'auth.resetTitle'.tr(),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  recovery ? 'auth.resetIntro'.tr() : 'auth.resetNeedLink'.tr(),
                ),
                const SizedBox(height: 24),
                if (recovery) ...[
                  TextField(
                    controller: _password,
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
                    onSubmitted: (_) => _save(),
                  ),
                ] else ...[
                  TextField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      labelText: 'auth.email'.tr(),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _requestLink(),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!.tr(),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : (recovery ? _save : _requestLink),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          recovery
                              ? 'auth.savePassword'.tr()
                              : 'auth.requestReset'.tr(),
                        ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => context.go('/login'),
                  child: Text('auth.signIn'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
