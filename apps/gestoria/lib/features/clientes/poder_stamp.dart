import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'poder_glance.dart';

/// Čip na seznamu a kartě. Složka ho neopakuje jiným názvem.
class PoderStamp extends StatelessWidget {
  const PoderStamp({super.key, required this.glance});

  final PoderGlance glance;

  @override
  Widget build(BuildContext context) {
    final (label, fill, ink) = switch (glance.kind) {
      PoderGlanceKind.missing => (
        'clients.poderMissing'.tr(),
        AppTheme.statusWatchSoft,
        AppTheme.statusWatch,
      ),
      PoderGlanceKind.present => (
        'clients.poder'.tr(),
        AppTheme.statusOkSoft,
        AppTheme.statusOk,
      ),
      PoderGlanceKind.expiring => (
        'clients.poderExpiring'.tr(),
        AppTheme.statusWarnSoft,
        AppTheme.statusWarn,
      ),
      PoderGlanceKind.expired => (
        'clients.poderExpired'.tr(),
        AppTheme.statusAlertSoft,
        AppTheme.statusAlert,
      ),
    };
    return Container(
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
  }
}
