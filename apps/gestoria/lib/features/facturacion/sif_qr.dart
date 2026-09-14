import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// PNG z `facturas.sif_qr_url` (data-URI nebo holé base64). HTTPS odkaz není obrázek.
Uint8List? sifQrPngBytes(String? stored) {
  final s = (stored ?? '').trim();
  if (s.isEmpty) return null;
  if (RegExp(r'^https?:\/\/', caseSensitive: false).hasMatch(s)) return null;
  const prefix = 'data:image/png;base64,';
  final payload = s.startsWith(prefix)
      ? s.substring(prefix.length)
      : (s.startsWith('data:') ? null : s.replaceAll(RegExp(r'\s'), ''));
  if (payload == null || payload.isEmpty) return null;
  try {
    return base64Decode(payload);
  } on FormatException {
    return null;
  }
}

Future<void> showSifQrDialog(
  BuildContext context, {
  String? qrStored,
  String? aeatUrl,
}) async {
  final png = sifQrPngBytes(qrStored);
  final url = (aeatUrl ?? '').trim();
  if (png == null && url.isEmpty) return;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text('facturacion.qr'.tr()),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (png != null)
                Image.memory(png, width: 220, height: 220, fit: BoxFit.contain),
              if (url.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('facturacion.aeatHint'.tr()),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('clients.cancel'.tr()),
          ),
          if (url.isNotEmpty)
            FilledButton(
              onPressed: () async {
                await launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                );
              },
              child: Text('facturacion.openAeat'.tr()),
            ),
        ],
      );
    },
  );
}
