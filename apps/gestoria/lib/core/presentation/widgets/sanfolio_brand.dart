import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Značka z návrhu Secure Flow. Text značky je i18n, rastr jen kresba.
class SanfolioMark extends StatelessWidget {
  const SanfolioMark({super.key, this.size = 28, this.filled = false});

  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      filled
          ? 'assets/branding/mark_filled.png'
          : 'assets/branding/mark.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'app.title'.tr(),
    );
  }
}

class SanfolioLockup extends StatelessWidget {
  const SanfolioLockup({super.key, this.height = 56});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/lockup.png',
      height: height,
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
      filterQuality: FilterQuality.high,
      semanticLabel: 'app.title'.tr(),
    );
  }
}
