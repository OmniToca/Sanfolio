import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'office_file_pick.dart';

/// Skutečný `<input type=file>` přes tlačítko.
/// `change` z DOM je mimo Flutter zónu — bez [Zone] Riverpod hodí minified:zt.
class OfficeFileHitLayer extends StatefulWidget {
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
  State<OfficeFileHitLayer> createState() => _OfficeFileHitLayerState();
}

class _OfficeFileHitLayerState extends State<OfficeFileHitLayer> {
  /// Zóna z [initState], ne z JS callbacku.
  late final Zone _zone;

  @override
  void initState() {
    super.initState();
    _zone = Zone.current;
  }

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
      ..multiple = widget.multiple;
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
        input.value = '';
        if (files == null || files.length == 0) return;
        if (widget.multiple) {
          final batch = <web.File>[];
          final n = files.length;
          final cap = n > officeFileBatchMax ? officeFileBatchMax : n;
          for (var i = 0; i < cap; i++) {
            final file = files.item(i);
            if (file != null) batch.add(file);
          }
          if (batch.isEmpty) return;
          unawaited(_zone.run(() => _readMany(batch)));
          return;
        }
        final file = files.item(0);
        if (file == null) return;
        unawaited(_zone.run(() => _read(file)));
      }.toJS,
    );
  }

  Future<void> _read(web.File file) async {
    try {
      final buffer = await file.arrayBuffer().toDart;
      final bytes = Uint8List.fromList(buffer.toDart.asUint8List());
      final picked = officeFileFromBytes(bytes, file.name);
      // `await` JS Promise skončí mimo zónu — Riverpod musí běžet uvnitř.
      _zone.run(() {
        if (!mounted) return;
        widget.onPicked?.call(picked);
      });
    } on OfficeFilePickException catch (e) {
      _zone.run(() {
        if (!mounted) return;
        widget.onError(officePickErrorI18n(e.code), e.code.name);
      });
    } on Object catch (e) {
      _zone.run(() {
        if (!mounted) return;
        widget.onError('folder.fileEmpty', _shortError(e));
      });
    }
  }

  Future<void> _readMany(List<web.File> files) async {
    final out = <PickedOfficeFile>[];
    try {
      for (final file in files) {
        final buffer = await file.arrayBuffer().toDart;
        final bytes = Uint8List.fromList(buffer.toDart.asUint8List());
        out.add(officeFileFromBytes(bytes, file.name));
      }
      _zone.run(() {
        if (!mounted) return;
        if (out.isEmpty) return;
        widget.onPickedMany?.call(out);
      });
    } on OfficeFilePickException catch (e) {
      _zone.run(() {
        if (!mounted) return;
        widget.onError(officePickErrorI18n(e.code), e.code.name);
      });
    } on Object catch (e) {
      _zone.run(() {
        if (!mounted) return;
        widget.onError('folder.fileEmpty', _shortError(e));
      });
    }
  }
}

String _shortError(Object error) {
  final raw = error.toString();
  if (raw.length <= 48) return raw;
  return raw.substring(0, 48);
}
