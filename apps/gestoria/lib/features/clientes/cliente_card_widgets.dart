import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_locales.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import 'cliente_audit.dart';

class ClienteLocaleMenu extends StatelessWidget {
  const ClienteLocaleMenu({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<String>(
      key: ValueKey(value),
      initialSelection: value,
      label: Text('clients.locale'.tr()),
      expandedInsets: EdgeInsets.zero,
      dropdownMenuEntries: [
        for (final code in appLocaleCodes)
          DropdownMenuEntry(value: code, label: 'lang.$code'.tr()),
      ],
      onSelected: (v) {
        if (v == null) return;
        onChanged(v);
      },
    );
  }
}

/// Stopa dění na kartě. Log se tu nedá smazat — append-only v DB.
class ClienteAuditSection extends ConsumerWidget {
  const ClienteAuditSection({required this.clienteId});

  final String clienteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clienteAuditProvider(clienteId));
    final when = DateFormat.yMMMd(context.locale.toString()).add_Hm();
    return ClienteCardSection(
      title: 'audit.title'.tr(),
      hint: 'audit.hint'.tr(),
      child: async.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, st) => Text('audit.loadError'.tr()),
        data: (events) {
          if (events.isEmpty) {
            return Text(
              'audit.empty'.tr(),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.pencil),
            );
          }
          return Column(
            children: [
              PreviewThenHistory(
                itemCount: events.length,
                expandLabel: 'common.history'.tr(),
                collapseLabel: 'common.historyHide'.tr(),
                builder: (context, i) => ClienteCardInsetRow(
                  title: events[i].actionI18nKey.tr(),
                  subtitle: [
                    if (_auditSubject(events[i]) case final subject?) subject,
                    when.format(events[i].createdAt.toLocal()),
                    events[i].actorLabel ?? 'audit.system'.tr(),
                    if (events[i].impersonating) 'audit.impersonation'.tr(),
                  ].join(' · '),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Co se otevřelo / nahrálo / změnilo. Akce samotná nestačí.
  String? _auditSubject(ClienteAuditEvent e) {
    final tipo = e.documentTipo;
    final tipoLabel = tipo == null ? null : 'docs.$tipo'.tr();
    final name = e.documentName;
    if (name != null && tipoLabel != null) return '$name · $tipoLabel';
    if (name != null) return name;
    if (tipoLabel != null) return tipoLabel;

    final asunto = e.asunto;
    if (asunto != null) return asunto;

    final contact = [
      if (e.contactNombre != null) e.contactNombre!,
      if (e.contactRelacion != null) e.contactRelacion!,
    ];
    if (contact.isNotEmpty) return contact.join(' · ');

    final fields = [
      for (final key in e.changedFields)
        if (auditClienteFieldI18n[key] != null)
          auditClienteFieldI18n[key]!.tr(),
    ];
    if (fields.isNotEmpty) return fields.join(', ');
    return null;
  }
}

/// Společný obal sekce karty — nadpis uvnitř, ne volně nad polem.
class ClienteCardSection extends StatelessWidget {
  const ClienteCardSection({
    required this.title,
    required this.child,
    this.hint,
    this.trailing,
  });

  final String title;
  final String? hint;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTheme.pencil),
              ),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// Řádek uvnitř karty. Ultrawide nesmí natáhnout ikony na kraj monitoru.
class ClienteCardInsetRow extends StatelessWidget {
  const ClienteCardInsetRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          if (leading != null) ...[
            IconTheme(
              data: const IconThemeData(color: AppTheme.pencil),
              child: leading!,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppTheme.pencil),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
    return Material(
      color: AppTheme.surfaceMuted,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: onTap == null
          ? row
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              child: row,
            ),
    );
  }
}

/// Dvě pole vedle sebe, pod 520 px pod sebou.
class ClienteCardFieldPair extends StatelessWidget {
  const ClienteCardFieldPair({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 12), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}
