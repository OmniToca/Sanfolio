import 'dart:ui_web' as ui_web;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web/web.dart' as web;

import '../../core/theme/app_theme.dart';
import 'posta_address.dart';
import 'posta_html.dart';

/// Čitelný náhled HTML mailu. Na webu iframe bez scriptů, jinak text.
class PostaHtmlBody extends StatelessWidget {
  const PostaHtmlBody({super.key, this.html, this.text});

  final String? html;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final rawHtml = html?.trim() ?? '';
    final rawText = text?.trim() ?? '';
    final readable = rawText.isNotEmpty
        ? rawText
        : htmlToReadableText(rawHtml);
    if (readable.isEmpty && rawHtml.isEmpty) {
      return Text('posta.noBody'.tr());
    }
    final urls = extractHttpUrls(readable);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: kIsWeb && rawHtml.isNotEmpty
                  ? _PostaHtmlFrame(html: rawHtml)
                  : SelectableText(
                      readable,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
            ),
            IconButton(
              tooltip: 'posta.copyBody'.tr(),
              icon: const Icon(Icons.copy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: readable));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('posta.copiedBody'.tr())),
                );
              },
            ),
          ],
        ),
        if (urls.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'posta.links'.tr(),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          for (final url in urls.take(12))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => launchUrl(Uri.parse(url)),
                  child: Text(url, textAlign: TextAlign.left),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _PostaHtmlFrame extends StatefulWidget {
  const _PostaHtmlFrame({required this.html});

  final String html;

  @override
  State<_PostaHtmlFrame> createState() => _PostaHtmlFrameState();
}

class _PostaHtmlFrameState extends State<_PostaHtmlFrame> {
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
