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
    this.onPicked,
    this.onPickedMany,
    this.multiple = false,
    this.icon = Icons.attach_file,
    this.outlined = false,
    this.enabled = true,
  });

  final String label;
  final IconData? icon;
  final bool outlined;
  final bool enabled;
  final bool multiple;
  final void Function(PickedOfficeFile file)? onPicked;
  final void Function(List<PickedOfficeFile> files)? onPickedMany;

  Future<void> _fallbackPick(BuildContext context) async {
    try {
      if (multiple) {
        final picked = await pickOfficeFiles();
        if (picked.isNotEmpty) onPickedMany?.call(picked);
        return;
      }
      final picked = await pickOfficeFile();
      if (picked != null) onPicked?.call(picked);
    } on OfficeFilePickException catch (e) {
      if (context.mounted) {
        showOfficeFileError(context, officePickErrorI18n(e.code), code: e.code.name);
      }
    } on Object {
      if (context.mounted) {
        showOfficeFileError(context, 'folder.fileEmpty', code: 'empty');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    void error(String key, String code) =>
        showOfficeFileError(context, key, code: code);
    final visual = outlined
        ? OutlinedButton.icon(
            onPressed: enabled ? () => _fallbackPick(context) : null,
            icon: Icon(icon ?? Icons.attach_file, size: 18),
            label: Text(label),
          )
        : icon == null
            ? TextButton(
                onPressed: enabled ? () => _fallbackPick(context) : null,
                child: Text(label),
              )
            : TextButton.icon(
                onPressed: enabled ? () => _fallbackPick(context) : null,
                icon: Icon(icon, size: 18),
                label: Text(label),
              );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40, minWidth: 48),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          visual,
          if (enabled)
            Positioned.fill(
              child: OfficeFileHitLayer(
                onPicked: onPicked,
                onPickedMany: onPickedMany,
                multiple: multiple,
                onError: error,
              ),
            ),
        ],
      ),
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
    code: _shortUploadCode(error),
  );
}

String _shortUploadCode(Object error) {
  final raw = error.toString().replaceAll('\n', ' ');
  if (raw.startsWith('minified:')) return raw;
  if (raw.length <= 40) return raw;
  return raw.substring(0, 40);
}
