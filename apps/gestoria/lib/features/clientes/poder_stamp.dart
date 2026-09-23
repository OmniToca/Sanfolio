import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../carpeta/carpeta_routes.dart';
import 'cliente_audit.dart';
import 'poder_glance.dart';

/// Čip na seznamu a kartě. Složka ho neopakuje jiným názvem.
class PoderStamp extends StatelessWidget {
  const PoderStamp({
    super.key,
    required this.glance,
    this.onOpen,
  });

  final PoderGlance glance;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final date = glance.expiresOn == null
        ? null
        : DateFormat.yMMMd(context.locale.toString()).format(glance.expiresOn!);
    final label = date == null
        ? poderStampI18nKey(glance).tr()
        : poderStampI18nKey(glance).tr(namedArgs: {'date': date});
    final (fill, ink) = switch (glance.kind) {
      PoderGlanceKind.missing => (
        AppTheme.statusWatchSoft,
        AppTheme.statusWatch,
      ),
      PoderGlanceKind.present => (AppTheme.statusOkSoft, AppTheme.statusOk),
      PoderGlanceKind.expiring => (
        AppTheme.statusWarnSoft,
        AppTheme.statusWarn,
      ),
      PoderGlanceKind.expired => (
        AppTheme.statusAlertSoft,
        AppTheme.statusAlert,
      ),
    };
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
    );
    if (onOpen == null) return chip;
    return Tooltip(
      message: 'clients.poderOpen'.tr(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          child: chip,
        ),
      ),
    );
  }
}

/// Kopie papíru, jinak šanon poderu na desce — tam žije datum po Guardar.
Future<void> openPoderGlanceSource({
  required BuildContext context,
  required PoderGlance glance,
  required String clienteId,
  String? tenantId,
}) async {
  final path = glance.storagePath?.trim() ?? '';
  final docId = glance.documentoId?.trim() ?? '';
  if (path.isNotEmpty) {
    final client = trySupabaseClient();
    if (client == null) return;
    try {
      final url =
          await client.storage.from('documentos').createSignedUrl(path, 120);
      if (tenantId != null && tenantId.isNotEmpty && docId.isNotEmpty) {
        await auditDocumentoOpen(
          documentId: docId,
          tenantId: tenantId,
          tipo: 'copia_poder',
          originalName: glance.originalName ?? '',
        );
      }
      await launchUrl(Uri.parse(url));
      return;
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('folder.openError'.tr())),
        );
      }
      return;
    }
  }
  if (!context.mounted) return;
  context.go(carpetaBloqueRoute(clienteId, 'poder'));
}
