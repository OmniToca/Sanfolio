import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Tužka finca: URBANA, ne bydliště klienta.
Future<({String direccion, String catastral})?> showFincaEditDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String direccion = '',
  String catastral = '',
}) async {
  final dir = TextEditingController(text: direccion);
  final cat = TextEditingController(text: catastral);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: dir,
            autofocus: true,
            decoration: InputDecoration(labelText: 'fields.address'.tr()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: cat,
            decoration: InputDecoration(labelText: 'fields.cadastral'.tr()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('clients.cancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  final address = dir.text.trim();
  final catastralOut = cat.text.trim();
  dir.dispose();
  cat.dispose();
  if (ok != true) return null;
  return (direccion: address, catastral: catastralOut);
}
