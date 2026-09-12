import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Společný login. Klíče: `auth.email`, `auth.password`, `auth.signIn`.
class LoginForm extends StatefulWidget {
  const LoginForm({
    super.key,
    required this.onSubmit,
    this.onForgotPassword,
    this.busy = false,
    this.errorText,
    this.notConfigured = false,
  });

  final Future<void> Function(String email, String password) onSubmit;

  /// Null = bez tlačítka (Support SMTP tady neřešíme).
  final Future<void> Function(String email)? onForgotPassword;
  final bool busy;
  final String? errorText;
  final bool notConfigured;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _forgotBusy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.busy || widget.notConfigured) return;
    await widget.onSubmit(_email.text.trim(), _password.text);
  }

  Future<void> _forgot() async {
    final cb = widget.onForgotPassword;
    if (cb == null || _forgotBusy || widget.notConfigured) return;
    setState(() => _forgotBusy = true);
    try {
      await cb(_email.text.trim());
    } finally {
      if (mounted) setState(() => _forgotBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canForgot = widget.onForgotPassword != null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.notConfigured) ...[
            Text('auth.notConfigured'.tr()),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _email,
            enabled: !widget.notConfigured,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            decoration: InputDecoration(
              labelText: 'auth.email'.tr(),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            enabled: !widget.notConfigured,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'auth.password'.tr(),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              widget.errorText!.tr(),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: widget.busy || widget.notConfigured ? null : _submit,
            child: widget.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('auth.signIn'.tr()),
          ),
          if (canForgot) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: widget.notConfigured || _forgotBusy ? null : _forgot,
              child: _forgotBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('auth.forgotPassword'.tr()),
            ),
          ],
        ],
      ),
    );
  }
}
