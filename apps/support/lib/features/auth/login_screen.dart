import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  String? _error;
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final snap = auth.valueOrNull;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('app.title'.tr(), style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('auth.intro'.tr()),
              const SizedBox(height: 24),
              LoginForm(
                notConfigured: snap?.configured == false,
                busy: _busy || auth.isLoading,
                errorText: _error ?? snap?.error,
                onSubmit: (email, password) async {
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  await ref.read(authControllerProvider.notifier).signIn(email, password);
                  if (!mounted) return;
                  setState(() => _busy = false);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
