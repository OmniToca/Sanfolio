import 'package:flutter/material.dart';

import 'office_file_pick.dart';

/// VM / testy: dialog z file_picker. Web má HTML overlay na tlačítku.
class OfficeFileHitLayer extends StatelessWidget {
  const OfficeFileHitLayer({
    super.key,
    this.onPicked,
    this.onPickedMany,
    this.multiple = false,
    required this.onError,
  });

  final void Function(PickedOfficeFile file)? onPicked;
  final void Function(List<PickedOfficeFile> files)? onPickedMany;
  final bool multiple;
  final void Function(String i18nKey, String code) onError;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        try {
          if (multiple) {
            final picked = await pickOfficeFiles();
            if (picked.isNotEmpty) onPickedMany?.call(picked);
            return;
          }
          final picked = await pickOfficeFile();
          if (picked != null) onPicked?.call(picked);
        } on OfficeFilePickException catch (e) {
          onError(officePickErrorI18n(e.code), e.code.name);
        } on Object {
          onError('folder.fileEmpty', 'empty');
        }
      },
    );
  }
}
