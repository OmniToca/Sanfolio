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
    this.stripe,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  final bool emphasized;
  /// Levý pruh — termín / díra, ne dekorace.
  final Color? stripe;

  @override
  Widget build(BuildContext context) {
    final mark = stripe ?? (emphasized ? AppTheme.stripeOn : null);
    final card = Container(
      margin: margin ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.rule),
        boxShadow: AppTheme.cardShadow,
      ),
      foregroundDecoration: mark == null
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border(
                left: BorderSide(color: mark, width: 4),
              ),
            ),
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

/// Nadpis a nápověda uvnitř karty, ne volně nad polem.
class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.child,
    this.title,
    this.hint,
    this.trailing,
  });

  final String? title;
  final String? hint;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            if (hint != null) ...[
              if (title != null) const SizedBox(height: 4),
              Text(
                hint!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.pencil,
                    ),
              ),
            ],
            if (title != null || hint != null) const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// Řádek uvnitř karty. Ikony drží u textu, ne u kraje monitoru.
class AppInsetRow extends StatelessWidget {
  const AppInsetRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.pencil,
                        ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
    return Material(
      color: AppTheme.surfaceMuted,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: onTap == null
          ? row
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              child: row,
            ),
    );
  }
}

/// Sdílené textové pole. Ve features nepoužívat surový [TextField] s vlastním borderem.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.minLines,
    this.maxLines = 1,
    this.keyboardType,
    this.alignLabelWithHint = false,
    this.prefixIcon,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final int? minLines;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool alignLabelWithHint;
  final Widget? prefixIcon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      minLines: minLines,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: prefixIcon == null ? label : null,
        hintText: prefixIcon == null ? null : label,
        prefixIcon: prefixIcon,
        alignLabelWithHint: alignLabelWithHint,
      ),
    );
  }
}

/// Masthead stránky místo holého Material AppBar.
class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    this.kicker,
    this.subtitle,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final String? kicker;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (kicker != null && kicker!.isNotEmpty)
                      Text(
                        kicker!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (actions.isNotEmpty)
                Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ),
          if (bottom != null) ...[
            const SizedBox(height: 16),
            bottom!,
          ],
        ],
      ),
    );
  }
}

/// Filtr jako razítko, ne Material chip.
class AppStamp extends StatelessWidget {
  const AppStamp({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.accentSoft : AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.rule,
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selected ? AppTheme.accent : AppTheme.pencil,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
          ),
        ),
      ),
    );
  }
}
