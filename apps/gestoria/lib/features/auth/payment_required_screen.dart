import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

class PaymentRequiredScreen extends ConsumerWidget {
  const PaymentRequiredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  'auth.paymentRequired'.tr(),
                  textAlign: TextAlign.center,
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
