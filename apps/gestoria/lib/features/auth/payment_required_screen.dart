import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class PaymentRequiredScreen extends StatelessWidget {
  const PaymentRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('auth.paymentRequired'.tr()),
        ),
      ),
    );
  }
}
