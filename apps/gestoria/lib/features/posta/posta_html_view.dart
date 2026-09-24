import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'posta_address.dart';
import 'posta_html.dart';
import 'posta_html_frame_stub.dart'
    if (dart.library.js_interop) 'posta_html_frame_web.dart';

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
                  ? PostaHtmlFrame(html: rawHtml)
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
