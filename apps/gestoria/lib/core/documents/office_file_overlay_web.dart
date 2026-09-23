import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'office_file_pick.dart';

/// Skutečný `<input type=file>` přes tlačítko.
/// Musí mít od rodiče pevnou šířku i výšku, jinak Safari uřízne overlay.
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
      ..accept = 'application/pdf,image/*,.pdf,.jpg,.jpeg,.png,.webp,.heic,.heif'
      ..multiple = widget.multiple;
    final s = input.style;
    s.setProperty('opacity', '0');
    s.setProperty('display', 'block');
    s.setProperty('width', '100%');
    s.setProperty('height', '100%');
    s.setProperty('cursor', 'pointer');
    s.setProperty('border', '0');
    s.setProperty('padding', '0');
    s.setProperty('margin', '0');
    s.setProperty('position', 'absolute');
    s.setProperty('inset', '0');
    s.setProperty('font-size', '64px');
    s.setProperty('overflow', 'hidden');
    s.setProperty('box-sizing', 'border-box');

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

  Future<PickedOfficeFile> _pickedOf(web.File file) async {
    final buffer = await file.arrayBuffer().toDart;
    final bytes = Uint8List.fromList(buffer.toDart.asUint8List());
    return officeFileFromBytes(bytes, file.name);
  }

  Future<void> _read(web.File file) async {
    try {
      final picked = await _pickedOf(file);
      _zone.run(() {
        if (!mounted) return;
        widget.onPicked?.call(picked);
      });
    } on OfficeFilePickException catch (e) {
      _emitError(officePickErrorI18n(e.code), e.code.name);
    } on Object catch (e) {
      _emitError('folder.fileEmpty', _shortError(e));
    }
  }

  /// Po jednom: 38 PDF naráz by Safari drželo v RAM a UI by vypadalo mrtvě.
  Future<void> _readMany(List<web.File> files) async {
    var delivered = 0;
    for (final file in files) {
      try {
        final picked = await _pickedOf(file);
        delivered++;
        _zone.run(() {
          if (!mounted) return;
          widget.onPickedMany?.call([picked]);
        });
      } on OfficeFilePickException catch (e) {
        _emitError(officePickErrorI18n(e.code), e.code.name);
      } on Object catch (e) {
        _emitError('folder.fileEmpty', _shortError(e));
      }
    }
    if (delivered == 0 && files.isNotEmpty) {
      _emitError('folder.fileEmpty', 'empty');
    }
  }

  void _emitError(String key, String code) {
    _zone.run(() {
      if (!mounted) return;
      widget.onError(key, code);
    });
  }
}

String _shortError(Object error) {
  final raw = error.toString();
  if (raw.length <= 48) return raw;
  return raw.substring(0, 48);
}
