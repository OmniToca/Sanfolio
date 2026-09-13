import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'office_file_pick.dart';

/// Skutečný `<input type=file>` přes tlačítko. Safari ignoruje `click()` na
/// `display:none` a event `cancel` často spolkne i vybraný soubor.
class OfficeFileHitLayer extends StatelessWidget {
  const OfficeFileHitLayer({
    super.key,
    required this.onPicked,
    required this.onError,
  });

  final void Function(PickedOfficeFile file) onPicked;
  final void Function(String i18nKey, String code) onError;

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      tagName: 'input',
      onElementCreated: _bind,
    );
  }

  void _bind(Object raw) {
    final input = raw as web.HTMLInputElement;
    input
      ..type = 'file'
      ..accept = '.pdf,.jpg,.jpeg,.png,.webp,.heic'
      ..multiple = false;
    final s = input.style;
    s.setProperty('opacity', '0');
    s.setProperty('width', '100%');
    s.setProperty('height', '100%');
    s.setProperty('cursor', 'pointer');
    s.setProperty('border', '0');
    s.setProperty('padding', '0');
    s.setProperty('margin', '0');
    s.setProperty('position', 'absolute');
    s.setProperty('left', '0');
    s.setProperty('top', '0');
    s.setProperty('font-size', '64px');

    input.addEventListener(
      'change',
      (web.Event _) {
        final files = input.files;
        final file =
            files != null && files.length > 0 ? files.item(0) : null;
        input.value = '';
        if (file == null) return;
        unawaited(_read(file));
      }.toJS,
    );
  }

  Future<void> _read(web.File file) async {
    try {
      final buffer = await file.arrayBuffer().toDart;
      final bytes = Uint8List.fromList(buffer.toDart.asUint8List());
      onPicked(officeFileFromBytes(bytes, file.name));
    } on OfficeFilePickException catch (e) {
      onError(officePickErrorI18n(e.code), e.code.name);
    } on Object {
      onError('folder.fileEmpty', 'empty');
    }
  }
}
