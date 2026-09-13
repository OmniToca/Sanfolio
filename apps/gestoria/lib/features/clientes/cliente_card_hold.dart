import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../core/identity/legal_hold.dart';
import '../../core/presentation/widgets/app_widgets.dart';

/// Owner zadá do kdy hold drží a proč. Default 6 let.
Future<({DateTime until, String reason})?> promptLegalHold(
  BuildContext context,
) async {
  final reason = TextEditingController();
  var until = defaultLegalHoldUntil(DateTime.now());
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text('clients.legalHoldAdd'.tr()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: until,
                        firstDate: DateTime(until.year - 1),
                        lastDate: DateTime(until.year + 20),
                      );
                      if (picked != null) setLocal(() => until = picked);
                    },
                    child: Text(
                      'clients.legalHoldUntil'.tr(
                        namedArgs: {'date': legalHoldUntilIso(until)},
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: reason,
                  label: 'clients.legalHoldReason'.tr(),
                  minLines: 2,
                  maxLines: 4,
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
                child: Text('clients.legalHoldAdd'.tr()),
              ),
            ],
          );
        },
      );
    },
  );
  final why = reason.text.trim();
  reason.dispose();
  if (ok != true || why.isEmpty) return null;
  return (until: until, reason: why);
}
