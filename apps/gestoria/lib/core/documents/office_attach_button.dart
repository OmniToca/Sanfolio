import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'office_file_overlay_stub.dart'
    if (dart.library.js_interop) 'office_file_overlay_web.dart';
import 'office_file_pick.dart';
import 'documento_storage.dart';

/// Přiložit: na webu klikne uživatel rovnou do `<input>`, ne do Flutter onPressed.
class OfficeAttachButton extends StatelessWidget {
  const OfficeAttachButton({
    super.key,
    required this.label,
    required this.onPicked,
    this.icon = Icons.attach_file,
    this.outlined = false,
    this.enabled = true,
  });

  final String label;
  final IconData? icon;
  final bool outlined;
  final bool enabled;
  final void Function(PickedOfficeFile file) onPicked;

  @override
  Widget build(BuildContext context) {
    final visual = outlined
        ? OutlinedButton.icon(
            onPressed: enabled ? () {} : null,
            icon: Icon(icon ?? Icons.attach_file, size: 18),
            label: Text(label),
          )
        : icon == null
            ? TextButton(
                onPressed: enabled ? () {} : null,
                child: Text(label),
              )
            : TextButton.icon(
                onPressed: enabled ? () {} : null,
                icon: Icon(icon, size: 18),
                label: Text(label),
              );
    return Stack(
      alignment: Alignment.center,
      children: [
        IgnorePointer(child: visual),
        if (enabled)
          Positioned.fill(
            child: OfficeFileHitLayer(
              onPicked: onPicked,
              onError: (key, code) => showOfficeFileError(
                context,
                key,
                code: code,
              ),
            ),
          ),
      ],
    );
  }
}

void showOfficeFileError(
  BuildContext context,
  String i18nKey, {
  String code = '',
}) {
  if (!context.mounted) return;
  final text = i18nKey == 'folder.uploadError' && code.isNotEmpty
      ? i18nKey.tr(namedArgs: {'code': code})
      : i18nKey.tr();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

void showOfficeUploadFailure(BuildContext context, Object error) {
  if (error is OfficeFilePickException) {
    showOfficeFileError(context, officePickErrorI18n(error.code));
    return;
  }
  if (error is OfficeUploadException) {
    final key = switch (error.code) {
      'too_big' => 'folder.fileTooBig',
      'bad_type' => 'folder.fileType',
      _ => 'folder.uploadError',
    };
    showOfficeFileError(context, key, code: error.code);
    return;
  }
  showOfficeFileError(
    context,
    'folder.uploadError',
    code: error.runtimeType.toString(),
  );
}
