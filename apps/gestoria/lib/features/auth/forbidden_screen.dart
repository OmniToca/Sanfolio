import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

class ForbiddenScreen extends ConsumerWidget {
  const ForbiddenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email =
        ref.watch(authControllerProvider).valueOrNull?.profile?.email.trim();
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'auth.forbidden'.tr(),
                  textAlign: TextAlign.center,
                ),
                if (email != null && email.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'auth.forbiddenAccount'.tr(namedArgs: {'email': email}),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'auth.forbiddenHint'.tr(
                    namedArgs: {'supportUrl': PortalUrls.supportAppBase()},
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).signOut(),
                  child: Text('auth.signOut'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
