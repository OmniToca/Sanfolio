import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../ai/escritura_parties.dart';
import 'carpeta_controller.dart';

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
                onShare: (v) => ctrl.setTitularShare(t.id, v),
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
    required this.onShare,
    required this.onRemove,
    this.onOpenCard,
  });

  final InmuebleTitular row;
  final bool isFolderOwner;
  final ValueChanged<String> onShare;
  final VoidCallback onRemove;
  final VoidCallback? onOpenCard;

  @override
  State<_TitularRow> createState() => _TitularRowState();
}

class _TitularRowState extends State<_TitularRow> {
  late final TextEditingController _share;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _share = TextEditingController(
      text: sharePercentFromBps(widget.row.cuotaBps),
    );
    _focus = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _TitularRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focus.hasFocus) return;
    final shown = sharePercentFromBps(widget.row.cuotaBps);
    if (_share.text != shown) _share.text = shown;
  }

  @override
  void dispose() {
    _share.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lado = widget.row.isComprador
        ? 'folder.ladoComprador'.tr()
        : 'folder.ladoVendedor'.tr();
    final bits = [
      widget.row.nombre,
      if (widget.row.nieRaw.isNotEmpty) widget.row.nieRaw,
      lado,
      if (widget.isFolderOwner) 'folder.titularFolder'.tr(),
      if (!widget.isFolderOwner && widget.onOpenCard != null)
        'folder.titularCard'.tr(),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(bits.join(' · ')),
          ),
          SizedBox(
            width: 88,
            child: AppTextField(
              controller: _share,
              focusNode: _focus,
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
