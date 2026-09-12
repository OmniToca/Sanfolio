import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/presentation/widgets/sanfolio_brand.dart';
import '../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final snap = auth.valueOrNull;
    final form = LoginForm(
      notConfigured: snap?.configured == false,
      busy: _busy || auth.isLoading,
      errorText: snap?.error,
      onForgotPassword: (email) async {
        if (email.isEmpty || !email.contains('@')) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('auth.emailRequired'.tr())),
          );
          return;
        }
        try {
          await ref.read(authControllerProvider.notifier).requestPasswordReset(email);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('auth.resetSent'.tr())),
          );
        } on Object {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('auth.resetError'.tr())),
          );
        }
      },
      onSubmit: (email, password) async {
        setState(() => _busy = true);
        await ref.read(authControllerProvider.notifier).signIn(email, password);
        if (mounted) setState(() => _busy = false);
      },
    );

    final wide = MediaQuery.sizeOf(context).width >= 860;
    final formBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!wide) ...[
          const SanfolioLockup(height: 52),
          const SizedBox(height: 16),
          Text('auth.intro'.tr()),
          const SizedBox(height: 28),
        ],
        form,
      ],
    );
    if (!wide) {
      return Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: AppCard(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: formBlock,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: ColoredBox(
              color: AppTheme.nav,
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTheme.navInk,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSm),
                          ),
                          child: const SanfolioMark(size: 30),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'app.title'.tr(),
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: AppTheme.navInk,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'app.tagline'.tr(),
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: AppTheme.navMuted,
                                letterSpacing: 1.4,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: 48,
                          height: 2,
                          color: AppTheme.accent,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'auth.intro'.tr(),
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: AppTheme.navMuted,
                                height: 1.45,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(48),
                child: AppCard(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                    child: formBlock,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
