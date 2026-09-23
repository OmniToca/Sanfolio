import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'office_file_pick.dart';

/// Skutečný `<input type=file>` přes tlačítko.
/// Musí mít od rodiče pevnou šířku i výšku, jinak Safari uřízne overlay.
/// `change` z DOM je mimo Flutter zónu — bez [Zone] Riverpod hodí minified:zt.
///
/// FileList je živý: `input.value = ''` ho hned vyprázdní. Soubory se musí
/// zkopírovat v tom samém synchronním handleru, jinak Přidat/Open nic neudělá
/// (Safari i Chrome).
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
  late final web.EventListener _onChange;
  web.HTMLInputElement? _input;

  @override
  void initState() {
    super.initState();
    _zone = Zone.current;
    _onChange = _handleChange.toJS;
  }

  @override
  void didUpdateWidget(covariant OfficeFileHitLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _input?.multiple = widget.multiple;
  }

  @override
  void dispose() {
    final input = _input;
    if (input != null) {
      input.removeEventListener('change', _onChange);
    }
    _input = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      tagName: 'input',
      onElementCreated: _bind,
    );
  }

  void _bind(Object raw) {
    final previous = _input;
    if (previous != null) {
      previous.removeEventListener('change', _onChange);
    }
    final input = raw as web.HTMLInputElement;
    _input = input;
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
    input.addEventListener('change', _onChange);
  }

  void _handleChange(web.Event _) {
    final input = _input;
    if (input == null) return;
    final captured = snapshotOfficeFileList(input.files);
    input.value = '';
    if (captured.isEmpty) return;
    final many = widget.onPickedMany;
    final one = widget.onPicked;
    final onError = widget.onError;
    final multiple = widget.multiple;
    unawaited(
      _zone.run(
        () => _deliver(
          captured,
          multiple: multiple,
          onPicked: one,
          onPickedMany: many,
          onError: onError,
        ),
      ),
    );
  }

  Future<PickedOfficeFile> _pickedOf(web.File file) async {
    final buffer = await file.arrayBuffer().toDart;
    final bytes = Uint8List.fromList(buffer.toDart.asUint8List());
    return officeFileFromBytes(bytes, file.name);
  }

  Future<void> _deliver(
    List<web.File> files, {
    required bool multiple,
    required void Function(PickedOfficeFile file)? onPicked,
    required void Function(List<PickedOfficeFile> files)? onPickedMany,
    required void Function(String i18nKey, String code) onError,
  }) async {
    if (!multiple) {
      try {
        final picked = await _pickedOf(files.first);
        _zone.run(() => onPicked?.call(picked));
      } on OfficeFilePickException catch (e) {
        _emitError(onError, officePickErrorI18n(e.code), e.code.name);
      } on Object catch (e) {
        _emitError(onError, 'folder.fileEmpty', _shortError(e));
      }
      return;
    }
    var delivered = 0;
    for (final file in files) {
      try {
        final picked = await _pickedOf(file);
        delivered++;
        _zone.run(() => onPickedMany?.call([picked]));
      } on OfficeFilePickException catch (e) {
        _emitError(onError, officePickErrorI18n(e.code), e.code.name);
      } on Object catch (e) {
        _emitError(onError, 'folder.fileEmpty', _shortError(e));
      }
    }
    if (delivered == 0 && files.isNotEmpty) {
      _emitError(onError, 'folder.fileEmpty', 'empty');
    }
  }

  void _emitError(
    void Function(String i18nKey, String code) onError,
    String key,
    String code,
  ) {
    _zone.run(() => onError(key, code));
  }
}

/// FileList po resetu inputu zmizí — nejdřív vlastní seznam [web.File].
List<web.File> snapshotOfficeFileList(
  web.FileList? list, {
  int max = officeFileBatchMax,
}) {
  if (list == null) return const [];
  return takeIndexedBatch(list.length, (i) => list.item(i), max: max);
}

String _shortError(Object error) {
  final raw = error.toString();
  if (raw.length <= 48) return raw;
  return raw.substring(0, 48);
}
