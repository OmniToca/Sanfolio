import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'office_file_overlay_stub.dart'
    if (dart.library.js_interop) 'office_file_overlay_web.dart';
import 'office_file_pick.dart';
import 'documento_storage.dart';

/// Přiložit: na webu klikne uživatel rovnou do `<input>`, ne do Flutter onPressed.
/// HtmlElementView musí mít pevnou výšku — v Row u stohu jinak Safari uřízne tlačítko.
class OfficeAttachButton extends StatelessWidget {
  const OfficeAttachButton({
    super.key,
    required this.label,
    this.caption,
    this.onPicked,
    this.onPickedMany,
    this.multiple = false,
    this.wide = false,
    this.icon = Icons.attach_file,
    this.outlined = false,
    this.enabled = true,
  });

  final String label;
  final String? caption;
  final IconData? icon;
  final bool outlined;
  final bool enabled;
  final bool multiple;
  final bool wide;
  final void Function(PickedOfficeFile file)? onPicked;
  final void Function(List<PickedOfficeFile> files)? onPickedMany;

  @override
  Widget build(BuildContext context) {
    void error(String key, String code) =>
        showOfficeFileError(context, key, code: code);
    // onPressed musí zůstat non-null, jinak Material šedne. Klik bere HitLayer —
    // druhý dialog z Flutteru by sebral soubory do jiného inputu a tenhle by
    // po Přidat zůstal prázdný.
    final visual = wide
        ? Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? () {} : null,
              child: _WideAttachLook(
                label: label,
                caption: caption,
                icon: icon ?? Icons.file_upload_outlined,
              ),
            ),
          )
        : outlined
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
    return SizedBox(
      width: wide ? double.infinity : 200,
      height: wide ? 200 : 40,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(child: visual),
          if (enabled)
            OfficeFileHitLayer(
              onPicked: onPicked,
              onPickedMany: onPickedMany,
              multiple: multiple,
              onError: error,
            ),
        ],
      ),
    );
  }
}

class _WideAttachLook extends StatelessWidget {
  const _WideAttachLook({
    required this.label,
    required this.icon,
    this.caption,
  });

  final String label;
  final String? caption;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.rule),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: AppTheme.accent),
            const SizedBox(height: 12),
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            if (caption != null && caption!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                caption!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.pencil,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
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
      'duplicate' => 'stoh.duplicateFile',
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
