import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'carpeta_controller.dart';
import 'documento_library.dart';

/// Výběr existujícího papíru z hromady. Nahrání z disku je jiné tlačítko.
Future<CarpetaDocumento?> showPilePickDialog(
  BuildContext context, {
  required List<CarpetaDocumento> papers,
}) {
  return showDialog<CarpetaDocumento>(
    context: context,
    builder: (ctx) {
      if (papers.isEmpty) {
        return AlertDialog(
          title: Text('folder.pilePickTitle'.tr()),
          content: Text('folder.pilePickEmpty'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('clients.cancel'.tr()),
            ),
          ],
        );
      }
      final pile = [
        for (final d in papers)
          if (d.albumKeys.isEmpty) d,
      ];
      final rest = [
        for (final d in papers)
          if (d.albumKeys.isNotEmpty) d,
      ];
      final ordered = [...pile, ...rest];
      return AlertDialog(
        title: Text('folder.pilePickTitle'.tr()),
        content: SizedBox(
          width: 420,
          height: 360,
          child: ListView.separated(
            itemCount: ordered.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final doc = ordered[i];
              final tipo = doc.tipo.trim().isEmpty || doc.tipo == 'other'
                  ? 'stoh.pile'.tr()
                  : 'docs.${doc.tipo}'.tr();
              return ListTile(
                dense: true,
                title: Text(doc.originalName),
                subtitle: Text(
                  tipo,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.pencil,
                      ),
                ),
                onTap: () => Navigator.pop(ctx, doc),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('clients.cancel'.tr()),
          ),
        ],
      );
    },
  );
}

/// Papíry, které toto album ještě nemá — odkaz, ne kopie.
List<CarpetaDocumento> papersForAlbumPick({
  required List<CarpetaDocumento> library,
  required String albumKey,
}) {
  return [
    for (final d in library)
      if (paperEligibleForAlbum(d.albumKeys, albumKey)) d,
  ];
}
