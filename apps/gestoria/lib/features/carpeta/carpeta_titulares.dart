import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../../core/identity/nie_persist.dart';
import '../ai/escritura_parties.dart';
import 'carpeta_controller.dart';

/// Čip strany této složky. Tužka je na řádku titulare, AI neukládá.
class FolderLadoBadge extends StatelessWidget {
  const FolderLadoBadge({
    super.key,
    required this.lado,
    this.showWhenUnknown = true,
  });

  final String? lado;
  final bool showWhenUnknown;

  @override
  Widget build(BuildContext context) {
    final known = normalizeFolderLado(lado);
    if (known == null && !showWhenUnknown) return const SizedBox.shrink();
    final label = switch (known) {
      'comprador' => 'folder.ladoComprador'.tr(),
      'vendedor' => 'folder.ladoVendedor'.tr(),
      _ => 'folder.ladoUnknown'.tr(),
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Spoluvlastníci na desce. Žije mimo `carpeta_screen`, ať obrazovka není obří.
class TitularesPanel extends ConsumerWidget {
  const TitularesPanel({super.key, required this.target});

  final CarpetaTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(carpetaControllerProvider(target)).valueOrNull;
    if (view == null || view.inmuebleId == null) {
      return const SizedBox.shrink();
    }
    final ctrl = ref.read(carpetaControllerProvider(target).notifier);
    final rows = view.titulares;
    final buyerSum = compradorCuotaBpsSum(rows);
    final buyers = [for (final t in rows) if (t.isComprador) t];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'folder.titulares'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FolderLadoBadge(lado: view.folderLado()),
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: Text(
                'folder.titularEmpty'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.pencil,
                    ),
              ),
            )
          else ...[
            if (buyers.isNotEmpty && buyerSum != 10000)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 8),
                child: Text(
                  'folder.titularShareWarn'.tr(
                    namedArgs: {'sum': sharePercentFromBps(buyerSum)},
                  ),
                  style: const TextStyle(color: AppTheme.statusAlert),
                ),
              ),
            for (final t in rows)
              _TitularRow(
                key: ValueKey(t.id),
                row: t,
                isFolderOwner: t.clienteId == view.clienteId,
                onNombre: (v) => ctrl.setTitularNombre(t.id, v),
                onNie: (v) => ctrl.setTitularNie(t.id, v),
                onShare: (v) => ctrl.setTitularShare(t.id, v),
                onLado: (v) => ctrl.setTitularLado(t.id, v),
                onRemove: () => ctrl.removeTitular(t.id),
                onOpenCard: (t.clienteId ?? '').isEmpty
                    ? null
                    : () => context.go('/clientes/${t.clienteId}'),
              ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () => _addTitular(context, ctrl),
              child: Text('folder.titularAdd'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitularRow extends StatefulWidget {
  const _TitularRow({
    super.key,
    required this.row,
    required this.isFolderOwner,
    required this.onNombre,
    required this.onNie,
    required this.onShare,
    required this.onLado,
    required this.onRemove,
    this.onOpenCard,
  });

  final InmuebleTitular row;
  final bool isFolderOwner;
  final ValueChanged<String> onNombre;
  final ValueChanged<String> onNie;
  final ValueChanged<String> onShare;
  final ValueChanged<String> onLado;
  final VoidCallback onRemove;
  final VoidCallback? onOpenCard;

  @override
  State<_TitularRow> createState() => _TitularRowState();
}

class _TitularRowState extends State<_TitularRow> {
  late final TextEditingController _nombre;
  late final TextEditingController _nie;
  late final TextEditingController _share;
  late final FocusNode _nombreFocus;
  late final FocusNode _nieFocus;
  late final FocusNode _shareFocus;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.row.nombre);
    _nie = TextEditingController(text: widget.row.nieRaw);
    _share = TextEditingController(
      text: sharePercentFromBps(widget.row.cuotaBps),
    );
    _nombreFocus = FocusNode();
    _nieFocus = FocusNode();
    _shareFocus = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _TitularRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_nombreFocus.hasFocus && _nombre.text != widget.row.nombre) {
      _nombre.text = widget.row.nombre;
    }
    if (syncDeskFieldFromParent(
          fieldKey: 'fields.nie',
          focused: _nieFocus.hasFocus,
        ) &&
        _nie.text != widget.row.nieRaw) {
      _nie.text = widget.row.nieRaw;
    }
    if (!_shareFocus.hasFocus) {
      final shown = sharePercentFromBps(widget.row.cuotaBps);
      if (_share.text != shown) _share.text = shown;
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _nie.dispose();
    _share.dispose();
    _nombreFocus.dispose();
    _nieFocus.dispose();
    _shareFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _nombre,
            focusNode: _nombreFocus,
            label: 'folder.titularNombre'.tr(),
            onChanged: widget.onNombre,
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AppTextField(
                  controller: _nie,
                  focusNode: _nieFocus,
                  label: 'folder.titularNie'.tr(),
                  onChanged: widget.onNie,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 88,
                child: AppTextField(
                  controller: _share,
                  focusNode: _shareFocus,
                  label: 'fields.sharePercent'.tr(),
                  keyboardType: TextInputType.number,
                  onChanged: widget.onShare,
                ),
              ),
              if (widget.onOpenCard != null)
                IconButton(
                  tooltip: 'folder.titularCard'.tr(),
                  onPressed: widget.onOpenCard,
                  icon: const Icon(Icons.person_outline),
                ),
              IconButton(
                tooltip: 'folder.titularRemove'.tr(),
                onPressed: widget.onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownMenu<String>(
                  key: ValueKey('lado-${widget.row.id}-${widget.row.lado}'),
                  initialSelection: widget.row.isComprador
                      ? 'comprador'
                      : 'vendedor',
                  label: Text('folder.titularLado'.tr()),
                  dropdownMenuEntries: [
                    DropdownMenuEntry(
                      value: 'comprador',
                      label: 'folder.ladoComprador'.tr(),
                    ),
                    DropdownMenuEntry(
                      value: 'vendedor',
                      label: 'folder.ladoVendedor'.tr(),
                    ),
                  ],
                  onSelected: (v) {
                    if (v != null) widget.onLado(v);
                  },
                ),
                Text(
                  [
                    if (widget.isFolderOwner) 'folder.titularFolder'.tr(),
                    if (!widget.isFolderOwner && widget.onOpenCard != null)
                      'folder.titularCard'.tr(),
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.pencil,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _addTitular(
  BuildContext context,
  CarpetaController ctrl,
) async {
  final nombre = TextEditingController();
  final nie = TextEditingController();
  final share = TextEditingController(text: '50');
  var lado = 'comprador';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text('folder.titularAdd'.tr()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  controller: nombre,
                  label: 'folder.titularNombre'.tr(),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: nie,
                  label: 'folder.titularNie'.tr(),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: share,
                  label: 'fields.sharePercent'.tr(),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                DropdownMenu<String>(
                  initialSelection: lado,
                  label: Text('folder.titularLado'.tr()),
                  dropdownMenuEntries: [
                    DropdownMenuEntry(
                      value: 'comprador',
                      label: 'folder.ladoComprador'.tr(),
                    ),
                    DropdownMenuEntry(
                      value: 'vendedor',
                      label: 'folder.ladoVendedor'.tr(),
                    ),
                  ],
                  onSelected: (v) {
                    if (v != null) setLocal(() => lado = v);
                  },
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
                child: Text('folder.titularAdd'.tr()),
              ),
            ],
          );
        },
      );
    },
  );
  final nameText = nombre.text;
  final nieText = nie.text;
  final shareText = share.text;
  nombre.dispose();
  nie.dispose();
  share.dispose();
  if (ok != true) return;
  try {
    await ctrl.addTitular(
      nombre: nameText,
      nie: nieText,
      lado: lado,
      sharePercent: shareText,
    );
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('folder.titularSaveError'.tr())),
      );
    }
  }
}
