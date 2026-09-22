import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/cents.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import 'office_modules_controller.dart';

/// Slot `settings.section`: co je v licenci a kolik kancelář platí.
/// Zapíná Support HQ, ne owner.
class OfficeModulesSection extends ConsumerWidget {
  const OfficeModulesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(officeLicenceProvider);
    return AppSectionCard(
      title: 'settings.modulesTitle'.tr(),
      hint: 'settings.modulesHint'.tr(),
      child: async.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, st) => Text('settings.loadError'.tr()),
        data: (quote) {
          final billed = [
            for (final line in quote.lines)
              if (line.billed) line,
          ];
          if (billed.isEmpty) {
            return Text('settings.modulesEmpty'.tr());
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final line in billed)
                AppInsetRow(
                  title: 'modules.${line.key}'.tr(),
                  subtitle: line.alwaysOn
                      ? 'settings.modulesIncluded'.tr()
                      : null,
                  trailing: Text(
                    'settings.modulesPrice'.tr(
                      namedArgs: {'amount': formatCents(line.cents)},
                    ),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              if (quote.discountBps > 0) ...[
                const SizedBox(height: 8),
                AppInsetRow(
                  title: 'settings.modulesDiscount'.tr(
                    namedArgs: {'percent': '${quote.discountPercent}'},
                  ),
                  trailing: Text(
                    'settings.modulesPrice'.tr(
                      namedArgs: {
                        'amount': '-${formatCents(quote.discountCents)}',
                      },
                    ),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppTheme.accent,
                        ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'settings.modulesMonthly'.tr(
                  namedArgs: {'amount': formatCents(quote.totalCents)},
                ),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          );
        },
      ),
    );
  }
}
