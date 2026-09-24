import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/staff_access.dart';
import '../../core/auth/staff_role.dart';
import '../../core/documents/office_attach_button.dart';
import '../../core/identity/nie_persist.dart';
import '../../core/documents/office_file_pick.dart';
import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/modules/slot_order.dart';
import '../../core/money/cents.dart';
import '../../core/money/provision.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../ai/ai_providers.dart';
import '../ai/documento_fields.dart';
import '../ai/escritura_parties.dart';
import '../ai/extract_queue_providers.dart';
import '../ai/extract_text.dart';
import '../ai/paper_glance.dart';
import '../ofertas/office_offer_compare.dart';
import '../expedientes/expediente_controller.dart';
import '../expedientes/expediente_estado.dart';
import '../inbox/inbox_providers.dart';
import '../clientes/cliente_audit.dart';
import '../settings/office_settings_controller.dart';
import '../settings/office_team_controller.dart';
import 'bloque_template.dart';
import 'carpeta_controller.dart';
import 'carpeta_print_open.dart';
import 'carpeta_routes.dart';
import 'carpeta_titulares.dart';
import 'finca_edit_dialog.dart';
import 'pile_pick_dialog.dart';

/// Text v políčku. Cents z DB se formátují; surové `100` by při sync smažalo eura.
String displayBloqueField(String field, String raw) {
  if (field == 'fields.received' || field == 'fields.invoiced') {
    if (raw.trim().isEmpty) return '';
    return formatCents(centsFromStored(raw));
  }
  return raw;
}

void _listenCarpetaNotice(
  BuildContext context,
  WidgetRef ref,
  CarpetaTarget target,
) {
  ref.listen<String?>(carpetaNoticeProvider(target), (_, next) {
    if (next == null || next.isEmpty || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(next)),
    );
    Future<void>.microtask(() {
      ref.read(carpetaNoticeProvider(target).notifier).state = null;
    });
  });
}

Future<void> _editFinca(
  BuildContext context,
  WidgetRef ref,
  CarpetaTarget target,
  CarpetaView view,
) async {
  final id = view.inmuebleId;
  if (id == null || id.isEmpty) return;
  final next = await showFincaEditDialog(
    context,
    title: 'folder.fincaEdit'.tr(),
    confirmLabel: 'folder.fincaSave'.tr(),
    direccion: view.inmuebleDireccion ?? '',
    catastral: view.inmuebleCatastral ?? '',
  );
  if (next == null || !context.mounted) return;
  if (next.direccion.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('clients.addressRequired'.tr())),
    );
    return;
  }
  final ok = await ref.read(carpetaControllerProvider(target).notifier)
      .updateInmuebleFinca(
    inmuebleId: id,
    direccion: next.direccion,
    catastral: next.catastral,
  );
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('folder.persistError'.tr())),
    );
  }
}

class CarpetaScreen extends ConsumerWidget {
  const CarpetaScreen({
    super.key,
    required this.clienteId,
    this.expedienteId,
    this.afterSkip = false,
  });

  final String clienteId;
  final String? expedienteId;
  /// Po Skip ze stohu: empty-state, ať nezbude prázdná deska bez návodu.
  final bool afterSkip;

  CarpetaTarget get _target =>
      CarpetaTarget(clienteId: clienteId, expedienteId: expedienteId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _listenCarpetaNotice(context, ref, _target);
    final async = ref.watch(carpetaControllerProvider(_target));
    return async.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text('folder.title'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        appBar: AppBar(
          title: Text('folder.title'.tr()),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/clientes'),
          ),
        ),
        body: Center(child: Text('folder.loadError'.tr())),
      ),
      data: (view) {
        final modules = ref.watch(tenantConfigProvider).valueOrNull;
        final settings = ref.watch(officeSettingsProvider).valueOrNull;
        final order = slotKeys(
          settings?.slotOrder,
          carpetaBlocksSlot,
        );
        final staffScope =
            ref.watch(myStaffScopeProvider).valueOrNull ?? StaffAccessScope.open;
        final isOwner = currentOfficeRole(
              ref.watch(authControllerProvider).valueOrNull ??
                  AuthSnapshot.signedOut,
            ) ==
            'owner';
        final templates = applySlotOrder(
          items: compraventaBloques.where((t) {
            if (!staffMaySeeBloque(
              isOwner: isOwner,
              scope: staffScope,
              templateKey: t.key,
            )) {
              return false;
            }
            if (t.moduleKey == 'carpeta_inmueble') return true;
            final m = GestoriaModuleKey.fromKey(t.moduleKey);
            return m == null || (modules?.isOn(m) ?? false);
          }).toList(),
          order: order,
          keyOf: (t) => t.key,
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(
              view.nombre.isEmpty ? 'folder.title'.tr() : view.nombre,
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/clientes/$clienteId'),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: () => context.go(
                    carpetaStohRoute(clienteId, expedienteId: expedienteId),
                  ),
                  icon: const Icon(Icons.layers_outlined, size: 18),
                  label: Text('stoh.attach'.tr()),
                ),
              ),
              IconButton(
                tooltip: 'folder.print'.tr(),
                icon: const Icon(Icons.print_outlined),
                onPressed: () => openCarpetaPrint(
                  view: view,
                  templates: templates,
                  officeName: (settings?.displayName ?? '').trim(),
                ),
              ),
              FeatureGate(
                module: GestoriaModule.messaging,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        context.go('/clientes/$clienteId/mensaje'),
                    icon: const Icon(Icons.mail_outline, size: 18),
                    label: Text('clients.writeEmail'.tr()),
                  ),
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: view.inmuebleId == null
                            ? null
                            : () => _editFinca(
                                  context,
                                  ref,
                                  _target,
                                  view,
                                ),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: Text(
                          view.inmuebleDireccion == null ||
                                  view.inmuebleDireccion!.isEmpty
                              ? 'folder.subtitle'.tr()
                              : view.inmuebleDireccion!,
                          style: const TextStyle(
                            color: AppTheme.pencil,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (view.inmuebleId != null)
                        FolderLadoBadge(lado: view.folderLado()),
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: FeatureGate(
            module: GestoriaModule.carpetaInmueble,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1100;
                final enabled = templates
                    .where(
                      (t) =>
                          (view.bloques[t.key] ?? const BloqueState(enabled: false))
                              .enabled,
                    )
                    .toList();
                final disabled = templates
                    .where(
                      (t) =>
                          !(view.bloques[t.key] ?? const BloqueState(enabled: false))
                              .enabled,
                    )
                    .toList();
                Widget cardFor(BloqueTemplate template, {required bool compact}) {
                  final state = view.bloques[template.key] ??
                      const BloqueState(enabled: false);
                  if (!compact && template.opensFromDesk) {
                    return _BloqueCover(
                      key: ValueKey(template.key),
                      target: _target,
                      template: template,
                      state: state,
                    );
                  }
                  return _BloqueCard(
                    key: ValueKey(template.key),
                    target: _target,
                    template: template,
                    state: state,
                    movements: view.movements,
                    clienteNombre: view.nombre,
                    clienteNie: view.bloques['cliente_snapshot']?.values['fields.nie'],
                    compact: compact,
                  );
                }

                Widget enabledGrid() {
                  if (enabled.isEmpty) return const SizedBox.shrink();
                  if (!wide) {
                    return Column(
                      children: [for (final t in enabled) cardFor(t, compact: false)],
                    );
                  }
                  final left = [for (var i = 0; i < enabled.length; i += 2) enabled[i]];
                  final right = [for (var i = 1; i < enabled.length; i += 2) enabled[i]];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            for (final t in left) cardFor(t, compact: false),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: [
                            for (final t in right) cardFor(t, compact: false),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppTheme.contentWide,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (view.expedienteId != null)
                              ExpedienteEstadoPicker(
                                estado: view.expedienteEstado,
                                onChanged: (v) async {
                                  await setExpedienteEstado(
                                    expedienteId: view.expedienteId!,
                                    estado: v,
                                  );
                                  ref.invalidate(
                                    carpetaControllerProvider(_target),
                                  );
                                  ref.invalidate(inboxFeedProvider);
                                },
                              ),
                            if (view.expedienteId != null)
                              const SizedBox(height: 16),
                            if (afterSkip && enabled.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: AppCard(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          'folder.emptyDesk'.tr(),
                                          style: const TextStyle(
                                            color: AppTheme.pencil,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: FilledButton.icon(
                                            onPressed: () => context.go(
                                              carpetaStohRoute(
                                                clienteId,
                                                expedienteId: expedienteId,
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.file_upload_outlined,
                                              size: 18,
                                            ),
                                            label: Text(
                                              'folder.emptyDeskStoh'.tr(),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            enabledGrid(),
                            if (disabled.isNotEmpty) ...[
                              const SizedBox(height: 24),
                              Text(
                                'folder.offBlocks'.tr(),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'folder.offBlocksHint'.tr(),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 12),
                              for (final t in disabled)
                                cardFor(t, compact: true),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Kryt bloku na deskách. Tužka a stoh papírů jsou na `/carpeta/:key`.
class _BloqueCover extends ConsumerWidget {
  const _BloqueCover({
    super.key,
    required this.target,
    required this.template,
    required this.state,
  });

  final CarpetaTarget target;
  final BloqueTemplate template;
  final BloqueState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = bloqueUiStatus(state.dbStatus);
    final ctrl = ref.read(carpetaControllerProvider(target).notifier);
    final view = ref.watch(carpetaControllerProvider(target)).valueOrNull;
    final summary = _coverSummary(template, state);
    final papers = state.documents.length;
    final canOpen = state.enabled || papers > 0;
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      emphasized: state.enabled,
      onTap: canOpen
          ? () => context.go(
                carpetaBloqueRoute(
                  target.clienteId,
                  template.key,
                  expedienteId: target.expedienteId,
                ),
              )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _BloqueWatchHeader(
                    title: template.labelI18n.tr(),
                    status: status,
                    folderLado: template.key == 'escritura'
                        ? view?.folderLado()
                        : null,
                    showFolderLado: template.key == 'escritura',
                  ),
                ),
                Tooltip(
                  message: 'folder.watchToggle'.tr(),
                  child: Switch(
                    value: state.enabled,
                    onChanged: (v) => _toggleCover(context, ctrl, v),
                  ),
                ),
              ],
            ),
            if (summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Text(
              'folder.paperCount'.tr(
                namedArgs: {'count': '$papers'},
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (state.enabled) _BloqueDocsProgress(template: template, state: state),
            if (canOpen)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => context.go(
                    carpetaBloqueRoute(
                      target.clienteId,
                      template.key,
                      expedienteId: target.expedienteId,
                    ),
                  ),
                  child: Text('folder.openBlock'.tr()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleCover(
    BuildContext context,
    CarpetaController ctrl,
    bool on,
  ) async {
    if (on) {
      await ctrl.setEnabled(template.key, true);
      return;
    }
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('folder.offReason'.tr()),
        content: TextField(
          controller: reasonCtrl,
          decoration: InputDecoration(
            hintText: 'folder.offReasonHint'.tr(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('ai.discard'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('folder.offConfirm'.tr()),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (ok != true || reason.isEmpty) return;
    await ctrl.setEnabled(template.key, false, reason: reason);
  }
}

/// Název vlevo, stav vedle. Switch je jinde — tužka ≠ hotovo.
class _BloqueWatchHeader extends StatelessWidget {
  const _BloqueWatchHeader({
    required this.title,
    required this.status,
    this.folderLado,
    this.showFolderLado = false,
  });

  final String title;
  final BloqueUiStatus status;
  final String? folderLado;
  final bool showFolderLado;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        Text(
          title,
          style: const TextStyle(
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        Chip(
          label: Text(
            statusLabel(status),
            style: TextStyle(
              fontSize: 12,
              color: bloqueStatusInk(status),
              fontWeight: FontWeight.w600,
            ),
          ),
          visualDensity: VisualDensity.compact,
          backgroundColor: bloqueStatusFill(status),
          side: BorderSide(color: bloqueStatusInk(status).withValues(alpha: 0.25)),
        ),
        if (showFolderLado) FolderLadoBadge(lado: folderLado),
      ],
    );
  }
}

class _BloqueDocsProgress extends StatelessWidget {
  const _BloqueDocsProgress({required this.template, required this.state});

  final BloqueTemplate template;
  final BloqueState state;

  @override
  Widget build(BuildContext context) {
    final hint = bloqueDocsHint(template, state);
    if (hint == null) return const SizedBox.shrink();
    final style = Theme.of(context).textTheme.bodySmall;
    if (hint.mode == RequiredDocsMode.any) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'folder.requiredDocsAny'.tr(
            namedArgs: {
              'types': template.requiredDocTypes
                  .map((t) => 'docs.$t'.tr())
                  .join(', '),
            },
          ),
          style: style,
        ),
      );
    }
    if (hint.satisfied) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hint.showBar) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: hint.barValue,
                color: AppTheme.statusWarn,
                backgroundColor: AppTheme.surfaceMuted,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            'folder.docsMissing'.tr(
              namedArgs: {
                'types': hint.missingTypes.map((t) => 'docs.$t'.tr()).join(', '),
              },
            ),
            style: style,
          ),
        ],
      ),
    );
  }
}

String _coverSummary(BloqueTemplate template, BloqueState state) {
  final parts = <String>[];
  for (final key in template.fieldKeys) {
    if (key == 'fields.remaining') continue;
    final v = (state.values[key] ?? '').trim();
    if (v.isEmpty) continue;
    parts.add(v);
    if (parts.length >= 3) break;
  }
  return parts.join(' · ');
}

List<CarpetaDocumento> _sortedPapers(List<CarpetaDocumento> docs) {
  final out = [...docs];
  out.sort((a, b) {
    final byDate =
        paperSortStamp(b.extracted).compareTo(paperSortStamp(a.extracted));
    if (byDate != 0) return byDate;
    return b.originalName.compareTo(a.originalName);
  });
  return out;
}

/// Šanon jednoho bloku: identita + papíry. Není to druhé ERP.
class BloqueScreen extends ConsumerWidget {
  const BloqueScreen({
    super.key,
    required this.clienteId,
    required this.bloqueKey,
    this.expedienteId,
  });

  final String clienteId;
  final String bloqueKey;
  final String? expedienteId;

  CarpetaTarget get _target =>
      CarpetaTarget(clienteId: clienteId, expedienteId: expedienteId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _listenCarpetaNotice(context, ref, _target);
    final staffScope =
        ref.watch(myStaffScopeProvider).valueOrNull ?? StaffAccessScope.open;
    final isOwner = currentOfficeRole(
          ref.watch(authControllerProvider).valueOrNull ??
              AuthSnapshot.signedOut,
        ) ==
        'owner';
    if (!staffMaySeeBloque(
      isOwner: isOwner,
      scope: staffScope,
      templateKey: bloqueKey,
    )) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.go(carpetaRoute(clienteId, expedienteId: expedienteId));
        }
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final async = ref.watch(carpetaControllerProvider(_target));
    BloqueTemplate? template;
    for (final t in compraventaBloques) {
      if (t.key == bloqueKey) template = t;
    }
    return async.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text('folder.title'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        appBar: AppBar(
          title: Text('folder.title'.tr()),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go(carpetaRoute(clienteId)),
          ),
        ),
        body: Center(child: Text('folder.loadError'.tr())),
      ),
      data: (view) {
        if (template == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text('folder.title'.tr()),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go(
                  carpetaRoute(clienteId, expedienteId: expedienteId),
                ),
              ),
            ),
            body: Center(child: Text('folder.loadError'.tr())),
          );
        }
        final bloque = template;
        final state =
            view.bloques[bloqueKey] ?? const BloqueState(enabled: false);
        // Chat dřív otevíral /carpeta/escritura i když blok je Nesledujeme.
        if (emptyOffBloque(state)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              context.go(
                carpetaRoute(clienteId, expedienteId: expedienteId),
              );
            }
          });
          return Scaffold(
            appBar: AppBar(title: Text(bloque.labelI18n.tr())),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(bloque.labelI18n.tr()),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go(
                carpetaRoute(clienteId, expedienteId: expedienteId),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        view.nombre.isEmpty
                            ? 'folder.subtitle'.tr()
                            : view.nombre,
                        style: const TextStyle(
                          color: AppTheme.pencil,
                          fontSize: 13,
                        ),
                      ),
                      if (bloqueKey == 'escritura')
                        FolderLadoBadge(lado: view.folderLado()),
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: FeatureGate(
            module: GestoriaModule.carpetaInmueble,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppTheme.contentWide,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OfficeOfferCompareCard(
                          clienteId: clienteId,
                          bloqueKey: bloqueKey,
                          glance: stackGlanceOf([
                            for (final d in state.documents)
                              (tipo: d.tipo, fields: d.extracted),
                          ]),
                        ),
                        _BloqueCard(
                          target: _target,
                          template: bloque,
                          state: state,
                          movements: view.movements,
                          clienteNombre: view.nombre,
                          clienteNie: view.bloques['cliente_snapshot']
                              ?.values['fields.nie'],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BloqueCard extends ConsumerStatefulWidget {
  const _BloqueCard({
    super.key,
    required this.target,
    required this.template,
    required this.state,
    this.movements = const [],
    this.clienteNombre = '',
    this.clienteNie,
    this.compact = false,
  });

  final CarpetaTarget target;
  final BloqueTemplate template;
  final BloqueState state;
  final List<ProvisionMovement> movements;
  final String clienteNombre;
  final String? clienteNie;
  final bool compact;

  @override
  ConsumerState<_BloqueCard> createState() => _BloqueCardState();
}

class _BloqueCardState extends ConsumerState<_BloqueCard> {
  late final Map<String, TextEditingController> _fields;
  late final Map<String, FocusNode> _focus;

  @override
  void initState() {
    super.initState();
    _fields = {
      for (final f in widget.template.fieldKeys)
        if (f != 'fields.remaining')
          f: TextEditingController(text: _displayField(f)),
    };
    _focus = {
      for (final f in _fields.keys) f: FocusNode(),
    };
  }

  @override
  void didUpdateWidget(covariant _BloqueCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Focusnuté pole je tužka. Parent rebuild / persist sem nesmí sahat —
    // na Flutter web to maže rozepsaný text (cents vs. zobrazení, starý snapshot).
    for (final e in _fields.entries) {
      final shown = _displayField(e.key);
      if (e.value.text == shown) continue;
      // Fokus drží tužku, kromě NIE po konfliktu (parent už vrátil živé číslo).
      if (!syncDeskFieldFromParent(
        fieldKey: e.key,
        focused: _focus[e.key]?.hasFocus ?? false,
      )) {
        continue;
      }
      e.value.text = shown;
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final template = widget.template;
    final state = widget.state;
    final status = bloqueUiStatus(state.dbStatus);
    final ctrl = ref.read(carpetaControllerProvider(widget.target).notifier);
    final papers = _sortedPapers(state.documents);
    final folderView =
        ref.watch(carpetaControllerProvider(widget.target)).valueOrNull;
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      emphasized: state.enabled,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _BloqueWatchHeader(
                    title: template.labelI18n.tr(),
                    status: status,
                    folderLado: template.key == 'escritura'
                        ? folderView?.folderLado()
                        : null,
                    showFolderLado: template.key == 'escritura',
                  ),
                ),
                Tooltip(
                  message: 'folder.watchToggle'.tr(),
                  child: Switch(
                    value: state.enabled,
                    onChanged: (v) => _toggle(ctrl, template.key, v),
                  ),
                ),
              ],
            ),
            _AiPrefillBar(
              target: widget.target,
              templateKey: template.key,
              fields: _fields,
            ),
            if (!widget.compact && state.enabled) ...[
              const SizedBox(height: 8),
              if (template.key == 'provision_factura')
                _provisionBody(context, ctrl)
              else
                for (final field in template.fieldKeys)
                  if (field == 'fields.remaining')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${field.tr()}: ${formatCents(_remainingCents(state))}',
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppTextField(
                        controller: _fields[field],
                        focusNode: _focus[field],
                        label: field.tr(),
                        onChanged: (v) => _onField(ctrl, template.key, field, v),
                      ),
                    ),
              if (template.key == 'escritura')
                TitularesPanel(target: widget.target),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OfficeAttachButton(
                      label: 'folder.attach'.tr(),
                      onPicked: (file) => _attachPicked(
                        context,
                        ctrl,
                        template.key,
                        file,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _attachFromPile(
                        context,
                        ctrl,
                        template,
                      ),
                      icon: const Icon(Icons.layers_outlined, size: 18),
                      label: Text('folder.attachFromPile'.tr()),
                    ),
                  ],
                ),
              ),
              if (template.requiredDocTypes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    (template.requiredDocsMode == RequiredDocsMode.any
                            ? 'folder.requiredDocsAny'
                            : 'folder.requiredDocs')
                        .tr(
                      namedArgs: {
                        'types': template.requiredDocTypes
                            .map((t) => 'docs.$t'.tr())
                            .join(', '),
                      },
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (state.documents.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Text(
                    'folder.papers'.tr(),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _PaperStackOverview(
                  bloqueKey: template.key,
                  papers: [
                    for (final d in papers)
                      (tipo: d.tipo, fields: d.extracted),
                  ],
                ),
                PreviewThenHistory(
                  itemCount: papers.length,
                  preview: 20,
                  gap: 0,
                  expandLabel: 'common.history'.tr(),
                  collapseLabel: 'common.historyHide'.tr(),
                  builder: (context, i) {
                    final doc = papers[i];
                    return _DocumentoForm(
                      target: widget.target,
                      templateKey: template.key,
                      doc: doc,
                      clienteNombre: widget.clienteNombre,
                      clienteNie: widget.clienteNie,
                      onOpen: () => _openDoc(context, ctrl, doc),
                      onRemove: () => _removeDoc(
                        context,
                        ctrl,
                        template.key,
                        doc.id,
                      ),
                    );
                  },
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _attachPicked(
    BuildContext context,
    CarpetaController ctrl,
    String templateKey,
    PickedOfficeFile file,
  ) async {
    CarpetaDocumento? attached;
    try {
      attached = await ctrl.attachDocument(
        templateKey: templateKey,
        bytes: file.bytes,
        originalName: file.name,
      );
    } on Object catch (e) {
      if (context.mounted) showOfficeUploadFailure(context, e);
      return;
    }
    if (attached == null) {
      if (context.mounted) {
        showOfficeFileError(context, 'folder.uploadError', code: 'empty');
      }
      return;
    }
    final tenantId = ctrl.state.valueOrNull?.tenantId;
    final clienteId = ctrl.state.valueOrNull?.clienteId;
    if (tenantId == null || clienteId == null) return;
    startExtractInBackground(
      tenantId: tenantId,
      clienteId: clienteId,
      storagePath: attached.storagePath,
      mime: mimeForOfficeFile(file.name, extension: file.extension),
      docTipo: attached.tipo,
      bloqueKey: templateKey,
      onDone: (draft) {
        if (draft != null &&
            !isExtractPending(draft.fields) &&
            !isExtractFailed(draft.fields)) {
          ref.read(aiPrefillProvider.notifier).state = draft;
        }
        ref.invalidate(liveAiDraftsProvider(clienteId));
        invalidateExtractQueue(ref);
      },
    );
    ref.invalidate(liveAiDraftsProvider(clienteId));
    invalidateExtractQueue(ref);
  }

  Future<void> _attachFromPile(
    BuildContext context,
    CarpetaController ctrl,
    BloqueTemplate template,
  ) async {
    final view = ref.read(carpetaControllerProvider(widget.target)).valueOrNull;
    if (view == null) return;
    final candidates = papersForAlbumPick(
      library: view.libraryDocuments,
      albumKey: template.key,
    );
    final picked = await showPilePickDialog(context, papers: candidates);
    if (picked == null || !context.mounted) return;
    final tipo = picked.tipo.trim().isEmpty || picked.tipo == 'other'
        ? guessDocumentoTipo(
            requiredDocTypes: template.requiredDocTypes,
            alreadyHave: {for (final d in widget.state.documents) d.tipo},
            originalName: picked.originalName,
          )
        : picked.tipo;
    final ok = await ctrl.setLibraryPlacement(
      documentId: picked.id,
      bloqueKey: template.key,
      tipo: tipo,
      on: true,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'stoh.placed'.tr() : 'stoh.saveError'.tr()),
      ),
    );
  }

  Future<void> _openDoc(
    BuildContext context,
    CarpetaController ctrl,
    CarpetaDocumento doc,
  ) async {
    if (doc.storagePurged) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('folder.purged'.tr())),
        );
      }
      return;
    }
    try {
      final url = await ctrl.signedUrl(doc.storagePath);
      if (url == null) throw StateError('url');
      final tenantId = ctrl.state.valueOrNull?.tenantId;
      if (tenantId != null) {
        await auditDocumentoOpen(
          documentId: doc.id,
          tenantId: tenantId,
          tipo: doc.tipo,
          originalName: doc.originalName,
        );
      }
      await launchUrl(Uri.parse(url));
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('folder.openError'.tr())),
        );
      }
    }
  }

  Future<void> _removeDoc(
    BuildContext context,
    CarpetaController ctrl,
    String templateKey,
    String documentId,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('folder.remove'.tr()),
        content: Text('folder.removeConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('clients.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('folder.remove'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ctrl.removeDocument(templateKey, documentId);
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('folder.removeError'.tr())),
        );
      }
    }
  }

  String _displayField(String field) {
    return displayBloqueField(field, widget.state.values[field] ?? '');
  }

  Future<void> _toggle(CarpetaController ctrl, String key, bool on) async {
    if (on) {
      await ctrl.setEnabled(key, true);
      return;
    }
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('folder.offReason'.tr()),
        content: TextField(
          controller: reasonCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'folder.offReasonHint'.tr(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('clients.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('folder.offConfirm'.tr()),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (ok != true || reason.isEmpty || !mounted) return;
    await ctrl.setEnabled(key, false, reason: reason);
  }

  void _onField(
    CarpetaController ctrl,
    String key,
    String field,
    String value,
  ) {
    if (field == 'fields.received' || field == 'fields.invoiced') {
      final cents = parseEurosToCents(value);
      ctrl.setField(key, field, cents == null ? '' : '$cents');
      return;
    }
    ctrl.setField(key, field, value);
  }

  int _remainingCents(BloqueState state) {
    return centsFromStored(state.values['fields.received']) -
        centsFromStored(state.values['fields.invoiced']);
  }

  Widget _provisionBody(BuildContext context, CarpetaController ctrl) {
    final rows = widget.movements;
    final received = provisionReceivedCents(rows);
    final invoiced = provisionInvoicedCents(rows);
    final remaining = provisionRemainingCents(rows);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${'fields.received'.tr()}: ${formatCents(received)}'),
        Text('${'fields.invoiced'.tr()}: ${formatCents(invoiced)}'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('${'fields.remaining'.tr()}: ${formatCents(remaining)}'),
        ),
        Text('provision.hint'.tr()),
        const SizedBox(height: 8),
        for (final row in rows)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('provision.kind.${row.kind}'.tr()),
            subtitle: Text(
              [
                '${formatCents(row.amountCents)} €',
                if (row.note != null && row.note!.isNotEmpty) row.note!,
              ].join(' · '),
            ),
            onTap: row.facturaId == null
                ? null
                : () => context.go('/facturacion/f/${row.facturaId}'),
            trailing: row.facturaId != null
                ? IconButton(
                    tooltip: 'facturacion.issued'.tr(),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    onPressed: () =>
                        context.go('/facturacion/f/${row.facturaId}'),
                  )
                : IconButton(
                    tooltip: 'folder.remove'.tr(),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => ctrl.removeProvisionMovement(row.id),
                  ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _addMovement(context, ctrl),
            icon: const Icon(Icons.add, size: 18),
            label: Text('provision.add'.tr()),
          ),
        ),
      ],
    );
  }

  Future<void> _addMovement(
    BuildContext context,
    CarpetaController ctrl,
  ) async {
    var kind = 'ingreso';
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('provision.add'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownMenu<String>(
              initialSelection: kind,
              label: Text('provision.kindLabel'.tr()),
              expandedInsets: EdgeInsets.zero,
              dropdownMenuEntries: [
                for (final k in provisionKinds)
                  DropdownMenuEntry(
                    value: k,
                    label: 'provision.kind.$k'.tr(),
                  ),
              ],
              onSelected: (v) {
                if (v != null) kind = v;
              },
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: amount,
              label: 'provision.amount'.tr(),
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: note,
              label: 'provision.note'.tr(),
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
            child: Text('provision.add'.tr()),
          ),
        ],
      ),
    );
    final cents = parseEurosToCents(amount.text);
    final noteText = note.text;
    amount.dispose();
    note.dispose();
    if (ok != true || cents == null || cents == 0) return;
    await ctrl.addProvisionMovement(
      kind: kind,
      amountCents: cents,
      note: noteText,
    );
  }
}

class _AiPrefillBar extends ConsumerWidget {
  const _AiPrefillBar({
    required this.target,
    required this.templateKey,
    required this.fields,
  });

  final CarpetaTarget target;
  final String templateKey;
  final Map<String, TextEditingController> fields;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clienteId = target.clienteId;
    final memory = ref.watch(aiPrefillProvider);
    final live =
        ref.watch(liveAiDraftsProvider(clienteId)).valueOrNull ?? const [];
    AiPrefillDraft? draft;
    if (memory != null &&
        memory.clienteId == clienteId &&
        memory.bloqueKey == templateKey &&
        (memory.storagePath == null || memory.storagePath!.isEmpty)) {
      draft = memory;
    } else {
      for (final d in live) {
        if (d.clienteId == clienteId &&
            d.bloqueKey == templateKey &&
            (d.storagePath == null || d.storagePath!.isEmpty)) {
          draft = d;
          break;
        }
      }
    }
    if (draft == null ||
        draft.clienteId != clienteId ||
        draft.bloqueKey != templateKey) {
      return const SizedBox.shrink();
    }
    final proposal = draft;
    final current = {
      for (final e in fields.entries) e.key: e.value.text,
    };
    final diffs = prefillDiffs(current: current, proposed: proposal.fields);
    if (diffs.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      color: AppTheme.proposal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ai.proposalBadge'.tr()),
          const SizedBox(height: 4),
          for (final d in diffs)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'ai.diffLine'.tr(
                  namedArgs: {
                    'field': d.fieldKey.tr(),
                    'current': d.current.isEmpty
                        ? 'ai.emptyValue'.tr()
                        : d.current,
                    'proposed': d.proposed,
                  },
                ),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: () async {
                  final ctrl =
                      ref.read(carpetaControllerProvider(target).notifier);
                  await ctrl.setEnabled(templateKey, true);
                  for (final e in proposal.fields.entries) {
                    ctrl.setField(templateKey, e.key, e.value);
                    fields[e.key]?.text = e.value;
                  }
                  await discardAiDraft(proposal.draftId);
                  ref.read(aiPrefillProvider.notifier).state = null;
                  ref.invalidate(liveAiDraftsProvider(clienteId));
                  invalidateExtractQueue(ref);
                },
                child: Text('ai.apply'.tr()),
              ),
              TextButton(
                onPressed: () async {
                  await discardAiDraft(proposal.draftId);
                  ref.read(aiPrefillProvider.notifier).state = null;
                  ref.invalidate(liveAiDraftsProvider(clienteId));
                  invalidateExtractQueue(ref);
                },
                child: Text('ai.discard'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaperStackOverview extends StatelessWidget {
  const _PaperStackOverview({required this.papers, this.bloqueKey = ''});

  final List<({String tipo, Map<String, String> fields})> papers;
  final String bloqueKey;

  @override
  Widget build(BuildContext context) {
    final glance = stackGlanceOf(papers);
    if (glance.invoiceCount == 0 && glance.policyPremiumCents == null) {
      return const SizedBox.shrink();
    }
    final last = glance.latest;
    final period = last == null ? '' : _officePeriod(context, last);
    final measure = supplyMeasureKey(bloqueKey).tr();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.accentSoft,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (glance.invoiceCount > 0)
                Text(
                  'folder.stackPaid'.tr(
                    namedArgs: {
                      'count': '${glance.invoiceCount}',
                      'total': formatCents(glance.paidCents),
                    },
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              if (last != null && period.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'folder.stackLast'.tr(
                    namedArgs: {
                      'period': period,
                      'amount': formatCents(last.amountCents ?? 0),
                    },
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.pencil,
                      ),
                ),
              ],
              if (glance.effectiveUnitCents != null &&
                  (bloqueKey == 'luz' ||
                      bloqueKey == 'gaz' ||
                      bloqueKey == 'agua')) ...[
                const SizedBox(height: 4),
                Text(
                  'folder.stackUnit'.tr(
                    namedArgs: {
                      'unit': formatCents(glance.effectiveUnitCents!),
                      'measure': measure,
                    },
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.pencil,
                      ),
                ),
              ],
              if (glance.annualCentsEstimate != null &&
                  glance.invoiceCount > 0 &&
                  bloqueKey != 'suma') ...[
                const SizedBox(height: 4),
                Text(
                  'folder.stackYear'.tr(
                    namedArgs: {
                      'amount': formatCents(glance.annualCentsEstimate!),
                    },
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.pencil,
                      ),
                ),
              ],
              if (glance.policyPremiumCents != null) ...[
                const SizedBox(height: 4),
                Text(
                  'folder.stackPremium'.tr(
                    namedArgs: {
                      'amount': formatCents(glance.policyPremiumCents!),
                    },
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.pencil,
                      ),
                ),
              ],
              if (glance.bars.length >= 2) ...[
                const SizedBox(height: 10),
                _AmountBars(cents: glance.bars),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountBars extends StatelessWidget {
  const _AmountBars({required this.cents});

  final List<int> cents;

  @override
  Widget build(BuildContext context) {
    final peak = cents.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 36,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < cents.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FractionallySizedBox(
                  heightFactor: peak == 0 ? 0 : cents[i] / peak,
                  alignment: Alignment.bottomCenter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: i == cents.length - 1
                          ? AppTheme.accent
                          : AppTheme.navSelected,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DocumentoForm extends ConsumerStatefulWidget {
  const _DocumentoForm({
    required this.target,
    required this.templateKey,
    required this.doc,
    required this.clienteNombre,
    this.clienteNie,
    required this.onOpen,
    required this.onRemove,
  });

  final CarpetaTarget target;
  final String templateKey;
  final CarpetaDocumento doc;
  final String clienteNombre;
  final String? clienteNie;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  ConsumerState<_DocumentoForm> createState() => _DocumentoFormState();
}

class _DocumentoFormState extends ConsumerState<_DocumentoForm> {
  var _details = false;

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final drafts =
        ref.watch(liveAiDraftsProvider(widget.target.clienteId)).valueOrNull ??
            const [];
    final memory = ref.watch(aiPrefillProvider);
    AiPrefillDraft? pending;
    if (memory != null && memory.storagePath == doc.storagePath) {
      pending = memory;
    } else {
      for (final d in drafts) {
        if (d.storagePath == doc.storagePath) {
          pending = d;
          break;
        }
      }
    }
    final values = displayDocumentoFields(
      fields: pending?.fields ?? doc.extracted,
      bodyText: doc.bodyText,
      clienteNombre: widget.clienteNombre,
      clienteNie: widget.clienteNie,
    );
    final glance = paperGlanceOf(tipo: doc.tipo, fields: values);
    final extra = extraPaperFieldKeys(values, tipo: doc.tipo);
    final nombre = (values['fields.nombre'] ?? '').trim();
    final mismatch = nombre.isNotEmpty &&
        !documentFitsCliente(
          cardName: widget.clienteNombre,
          cardNie: widget.clienteNie,
          fields: values,
        );
    final period = _officePeriod(context, glance);
    final hasGlance = glance.isInvoice &&
        (period.isNotEmpty || glance.amountCents != null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: pending != null ? AppTheme.proposal : AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: AppTheme.rule),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasGlance && period.isNotEmpty
                              ? period
                              : 'docs.${doc.tipo}'.tr(),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (hasGlance) 'docs.${doc.tipo}'.tr(),
                            if (glance.consumption != null)
                              glance.consumption!,
                            doc.originalName,
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.pencil,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (glance.amountCents != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 4),
                      child: Text(
                        'folder.money'.tr(
                          namedArgs: {
                            'amount': formatCents(glance.amountCents!),
                          },
                        ),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: AppTheme.accent,
                            ),
                      ),
                    ),
                  IconButton(
                    tooltip: doc.storagePurged
                        ? 'folder.purged'.tr()
                        : 'folder.original'.tr(),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    onPressed: doc.storagePurged ? null : widget.onOpen,
                  ),
                  IconButton(
                    tooltip: 'ai.extract'.tr(),
                    icon: const Icon(Icons.document_scanner_outlined, size: 18),
                    onPressed: doc.storagePurged
                        ? null
                        : () {
                            final tenantId = ref
                                .read(carpetaControllerProvider(widget.target))
                                .valueOrNull
                                ?.tenantId;
                            if (tenantId == null) return;
                            startExtractInBackground(
                              tenantId: tenantId,
                              clienteId: widget.target.clienteId,
                              storagePath: doc.storagePath,
                              mime: mimeForOfficeFile(doc.originalName),
                              docTipo: looksLikeEscrituraName(doc.originalName)
                                  ? 'copia_escritura'
                                  : doc.tipo,
                              bloqueKey: widget.templateKey,
                              onDone: (draft) {
                                if (draft != null &&
                                    !isExtractPending(draft.fields) &&
                                    !isExtractFailed(draft.fields)) {
                                  ref.read(aiPrefillProvider.notifier).state =
                                      draft;
                                }
                                ref.invalidate(
                                  liveAiDraftsProvider(
                                    widget.target.clienteId,
                                  ),
                                );
                                invalidateExtractQueue(ref);
                              },
                            );
                          },
                  ),
                  IconButton(
                    tooltip: 'folder.remove'.tr(),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: widget.onRemove,
                  ),
                ],
              ),
              if ((values['fields.folderLado'] ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: FolderLadoBadge(
                    lado: values['fields.folderLado'],
                    showWhenUnknown: false,
                  ),
                ),
              if (mismatch)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    'folder.nameMismatch'.tr(
                      namedArgs: {
                        'doc': nombre,
                        'card': widget.clienteNombre,
                      },
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (isExtractPending(values))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('ai.readingDoc'.tr()),
                )
              else if (isExtractFailed(values))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('folder.extractError'.tr()),
                ),
              if (showDocumentoBodyOnPaper(
                hasShownFields: hasGlance || extra.isNotEmpty,
                bodyText: doc.bodyText,
              ))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    doc.bodyText!.trim(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (doc.storagePurged)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('folder.purged'.tr()),
                ),
              if (_details) ...[
                if (glance.invoiceNo != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${'fields.invoiceNo'.tr()}: ${glance.invoiceNo}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                for (final k in extra)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${k.tr()}: ${shownFieldValue(k, values[k]!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
              if (extra.isNotEmpty || glance.invoiceNo != null)
                TextButton(
                  onPressed: () => setState(() => _details = !_details),
                  child: Text(
                    _details
                        ? 'folder.paperDetailsHide'.tr()
                        : 'folder.paperDetails'.tr(),
                  ),
                ),
              if (pending != null &&
                  !isExtractPending(values) &&
                  !isExtractFailed(values))
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: () async {
                      final draft = pending!;
                      final ctrl = ref.read(
                        carpetaControllerProvider(widget.target).notifier,
                      );
                      final skippedParties = await ctrl.saveDocumentoExtracted(
                        templateKey: widget.templateKey,
                        documentId: doc.id,
                        fields: draft.fields,
                      );
                      await discardAiDraft(draft.draftId);
                      ref.read(aiPrefillProvider.notifier).state = null;
                      ref.invalidate(
                        liveAiDraftsProvider(widget.target.clienteId),
                      );
                      invalidateExtractQueue(ref);
                      final notice = applyExtractNotice(
                        mismatch: mismatch,
                        skippedDeedParties: skippedParties,
                      );
                      if (notice != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(notice.tr())),
                        );
                      }
                    },
                    child: Text('ai.apply'.tr()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _officeDay(BuildContext context, String raw) {
  final d = DateTime.tryParse(raw);
  if (d == null) return raw;
  return DateFormat.yMMMd(context.locale.toString()).format(d);
}

String _officePeriod(BuildContext context, PaperGlance g) {
  final from = g.periodFrom;
  final to = g.periodTo;
  if (from == null && to == null) return '';
  if (from == null) return _officeDay(context, to!);
  if (to == null) return _officeDay(context, from);
  return '${_officeDay(context, from)} – ${_officeDay(context, to)}';
}

