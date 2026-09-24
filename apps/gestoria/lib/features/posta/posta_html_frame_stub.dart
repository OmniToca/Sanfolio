import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'posta_html.dart';

/// VM / test: bez iframe, jen čitelný text.
class PostaHtmlFrame extends StatelessWidget {
  const PostaHtmlFrame({super.key, required this.html});

  final String html;

  @override
  Widget build(BuildContext context) {
    final readable = htmlToReadableText(html);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.rule),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          readable.isEmpty ? html : readable,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
