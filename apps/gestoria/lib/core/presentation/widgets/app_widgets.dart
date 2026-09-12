import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Sdílená karta. Ve features nepoužívat surový [Card].
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.margin,
    this.emphasized = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.rule),
        boxShadow: AppTheme.cardShadow,
      ),
      foregroundDecoration: emphasized
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: const Border(
                left: BorderSide(color: AppTheme.stripeOn, width: 4),
              ),
            )
          : null,
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: card,
      ),
    );
  }
}

/// Šířka čitelné desky. Ultrawide nesmí natáhnout formuláře přes celý monitor.
class AppContent extends StatelessWidget {
  const AppContent({
    super.key,
    required this.child,
    this.maxWidth = AppTheme.contentMax,
    this.padding = const EdgeInsets.fromLTRB(24, 12, 24, 48),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < maxWidth
            ? constraints.maxWidth
            : maxWidth;
        Widget box = Padding(padding: padding, child: child);
        box = SizedBox(width: width, child: box);
        if (constraints.maxHeight.isFinite) {
          box = SizedBox(height: constraints.maxHeight, child: box);
        }
        return Align(alignment: Alignment.topCenter, child: box);
      },
    );
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
      decoration: InputDecoration(labelText: label),
    );
  }
}
