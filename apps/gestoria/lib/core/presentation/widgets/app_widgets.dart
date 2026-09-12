import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Sdílená karta. Ve features nepoužívat surový [Card].
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.margin});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      margin: margin ?? EdgeInsets.zero,
      elevation: 0,
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: const BorderSide(color: AppTheme.rule),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(onTap: onTap, child: card);
  }
}

/// Sdílené textové pole. Ve features nepoužívat surový [TextField] s vlastním borderem.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.onChanged,
  });

  final String label;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
