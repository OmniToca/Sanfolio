import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../settings/office_settings_controller.dart';
import 'posta_providers.dart';

/// Slot `settings.section`: veřejná schránka + kam Gmail posílá kopii.
class PostaIngestSection extends ConsumerStatefulWidget {
  const PostaIngestSection({super.key, required this.settings});

  final OfficeSettings settings;

  @override
  ConsumerState<PostaIngestSection> createState() => _PostaIngestSectionState();
}

class _PostaIngestSectionState extends ConsumerState<PostaIngestSection> {
  late final TextEditingController _office;
  late final TextEditingController _phone;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _office = TextEditingController(text: widget.settings.officeEmail);
    _phone = TextEditingController(text: widget.settings.officePhone);
  }

  @override
  void didUpdateWidget(covariant PostaIngestSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.officeEmail != widget.settings.officeEmail &&
        _office.text != widget.settings.officeEmail) {
      _office.text = widget.settings.officeEmail;
    }
    if (oldWidget.settings.officePhone != widget.settings.officePhone &&
        _phone.text != widget.settings.officePhone) {
      _phone.text = widget.settings.officePhone;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _office.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(postaAccountProvider);
    return FeatureGate(
      module: GestoriaModule.messaging,
      child: AppSectionCard(
        title: 'posta.ingestTitle'.tr(),
        hint: 'posta.ingestHint'.tr(),
        child: async.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, st) => Text('posta.loadError'.tr()),
          data: (account) {
            final addr = account?.ingestAddress ?? '';
            if (addr.isEmpty) {
              return Text('posta.loadError'.tr());
            }
            final steps = [
              'posta.ingestStep1'.tr(),
              'posta.ingestStep2'.tr(),
              'posta.ingestStep3'.tr(),
              'posta.ingestStep4'.tr(),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'posta.officeEmail'.tr(),
                  controller: _office,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), () {
                      ref
                          .read(officeSettingsProvider.notifier)
                          .setOfficeEmail(v);
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'posta.officeEmailHint'.tr(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.pencil,
                      ),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'posta.officePhone'.tr(),
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), () {
                      ref
                          .read(officeSettingsProvider.notifier)
                          .setOfficePhone(v);
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'posta.officePhoneHint'.tr(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.pencil,
                      ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        addr,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'posta.ingestCopy'.tr(),
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: addr));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('posta.ingestCopied'.tr())),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${i + 1}. ${steps[i]}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.pencil,
                          ),
                    ),
                  ),
                Text(
                  'posta.ingestManyOffices'.tr(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
