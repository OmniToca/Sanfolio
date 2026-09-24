import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../core/theme/app_theme.dart';
import 'posta_html.dart';

/// Web: iframe bez scriptů. ui_web jen tady, ať VM test projde.
class PostaHtmlFrame extends StatefulWidget {
  const PostaHtmlFrame({super.key, required this.html});

  final String html;

  @override
  State<PostaHtmlFrame> createState() => _PostaHtmlFrameState();
}

class _PostaHtmlFrameState extends State<PostaHtmlFrame> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType =
        'posta-html-${identityHashCode(this)}-${DateTime.now().microsecondsSinceEpoch}';
    final src = wrapPostaHtml(sanitizePostaHtml(widget.html));
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int id) {
      final iframe = web.HTMLIFrameElement()
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#FFFCF8';
      iframe.setAttribute('srcdoc', src);
      iframe.setAttribute(
        'sandbox',
        'allow-popups allow-popups-to-escape-sandbox',
      );
      iframe.setAttribute('referrerpolicy', 'no-referrer');
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.rule),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: SizedBox(
          height: 420,
          width: double.infinity,
          child: HtmlElementView(viewType: _viewType),
        ),
      ),
    );
  }
}
