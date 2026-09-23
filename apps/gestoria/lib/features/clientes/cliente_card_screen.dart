import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/staff_role.dart';
import '../../core/documents/bloque_field_keys.dart';
import '../../core/documents/office_attach_button.dart';
import '../../core/documents/office_file_pick.dart';
import '../../core/i18n/app_locales.dart';
import '../../core/identity/legal_hold.dart';
import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../../core/time/office_date.dart';
import '../ai/ai_providers.dart';
import '../ai/documento_fields.dart';
import '../ai/escritura_parties.dart';
import '../ai/extract_queue_providers.dart';
import '../ai/extract_text.dart';
import 'cliente_audit.dart';
import 'cliente_card_controller.dart';
import 'cliente_card_hold.dart';
import 'cliente_card_widgets.dart';
import 'clientes_providers.dart';
import 'reach_gaps.dart';
import 'reach_gaps_providers.dart';
import '../expedientes/expediente_catalog.dart';
import '../expedientes/expediente_controller.dart';
import '../facturacion/cliente_facturas_section.dart';
import '../inbox/inbox_providers.dart';
import '../mensajes/mensaje_history.dart';
import '../posta/posta_cliente_section.dart';
import '../settings/office_settings_controller.dart';
import 'poder_stamp.dart';

class ClienteCardScreen extends ConsumerStatefulWidget {
  const ClienteCardScreen({super.key, required this.clienteId});

  final String clienteId;

  @override
  ConsumerState<ClienteCardScreen> createState() => _ClienteCardScreenState();
}

class _ClienteCardScreenState extends ConsumerState<ClienteCardScreen> {
  final _nombre = TextEditingController();
  final _nie = TextEditingController();
  final _email = TextEditingController();
  final _tel = TextEditingController();
  final _iban = TextEditingController();
  final _notas = TextEditingController();
  String _locale = 'cs';
  var _filledFor = '';
  var _busy = false;
  var _openLoggedFor = '';
  final _extractStarted = <String>{};

  @override
  void didUpdateWidget(ClienteCardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clienteId != widget.clienteId) {
      _filledFor = '';
      _openLoggedFor = '';
      _extractStarted.clear();
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _nie.dispose();
    _email.dispose();
    _tel.dispose();
    _iban.dispose();
    _notas.dispose();
    super.dispose();
  }

  void _fill(ClienteCard card) {
    if (_filledFor == card.id && !card.deleted) {
      // Po uložení provider refreshne — nenechat přepsat rozepsané pole.
      return;
    }
    _filledFor = card.id;
    _nombre.text = card.nombre;
    _nie.text = card.nie ?? '';
    _email.text = card.email ?? '';
    _tel.text = card.tel ?? '';
    _iban.text = card.iban ?? '';
    _notas.text = card.notas ?? '';
    _locale = appLocaleCodes.contains(card.locale) ? card.locale : 'cs';
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(clienteCardProvider(widget.clienteId));
    final auth = ref.watch(authControllerProvider).valueOrNull;
    final owner = auth != null && canRestoreDeleted(auth);
    final showAudit = auth != null && canViewClienteAudit(auth);
    _logOpenOnce(auth);

    return async.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text('clients.cardTitle'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        appBar: AppBar(
          title: Text('clients.cardTitle'.tr()),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/clientes'),
          ),
        ),
        body: Center(child: Text('clients.cardLoadError'.tr())),
      ),
      data: (card) {
        _fill(card);
        _scheduleExtracts(card);
        final messagingOn = ref.watch(tenantConfigProvider).maybeWhen(
          data: (c) => c.isOn(GestoriaModule.messaging),
          orElse: () => false,
        );
        return Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1100;
              return ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppTheme.contentWide,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _cardHeader(card, messagingOn: messagingOn),
                          if (card.deleted) ...[
                            AppCard(
                              child: ListTile(
                                leading: const Icon(Icons.inventory_2_outlined),
                                title: Text('clients.deletedBanner'.tr()),
                                subtitle: owner
                                    ? null
                                    : Text('clients.onlyOwnerRestore'.tr()),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (owner)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton(
                                  onPressed: _busy ? null : () => _restore(),
                                  child: Text('clients.restore'.tr()),
                                ),
                              ),
                          ] else ...[
                            if (wide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Kontakt a spisy pod údaje — vedle dokladů by jinak zela díra.
                                  Expanded(
                                    flex: 5,
                                    child: Column(
                                      children: [
                                        _identityCard(card),
                                        const SizedBox(height: 16),
                                        _contactsCard(card),
                                        const SizedBox(height: 16),
                                        _expedientesCard(),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    flex: 4,
                                    child: Column(
                                      children: [
                                        ClientePostaSection(
                                          clienteId: widget.clienteId,
                                        ),
                                        const SizedBox(height: 16),
                                        _documentsCard(card),
                                        const SizedBox(height: 16),
                                        ClienteFacturasSection(
                                          clienteId: widget.clienteId,
                                        ),
                                        const SizedBox(height: 16),
                                        ClienteMensajeHistory(
                                          clienteId: widget.clienteId,
                                          clientLocale: card.locale,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            else ...[
                              _identityCard(card),
                              const SizedBox(height: 16),
                              ClientePostaSection(
                                clienteId: widget.clienteId,
                              ),
                              const SizedBox(height: 16),
                              _documentsCard(card),
                              const SizedBox(height: 16),
                              ClienteFacturasSection(
                                clienteId: widget.clienteId,
                              ),
                              const SizedBox(height: 16),
                              ClienteMensajeHistory(
                                clienteId: widget.clienteId,
                                clientLocale: card.locale,
                              ),
                              const SizedBox(height: 16),
                              _contactsCard(card),
                              const SizedBox(height: 16),
                              _expedientesCard(),
                            ],
                          ],
                          if (showAudit) ...[
                            const SizedBox(height: 16),
                            ClienteAuditSection(clienteId: widget.clienteId),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Složka a e-mail jako popsaná tlačítka, ne jako dvě ikony v AppBar.
  Widget _cardHeader(ClienteCard card, {required bool messagingOn}) {
    final nie = card.nie?.trim();
    final subtitle = [
      if (card.isCoOwnerOnly)
        'clients.coOwner'.tr(
          namedArgs: {
            'owner': card.coOwnerFolderNombre ?? '',
            'address': card.coOwnerDireccion ?? '',
          },
        ),
      if ((card.email ?? '').trim().isNotEmpty) card.email!.trim(),
      if ((card.tel ?? '').trim().isNotEmpty) card.tel!.trim(),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.go('/clientes'),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text('nav.clients'.tr()),
          ),
        ),
        AppPageHeader(
          kicker: nie == null || nie.isEmpty ? 'clients.cardTitle'.tr() : nie,
          title: card.nombre.isEmpty ? 'clients.cardTitle'.tr() : card.nombre,
          subtitle: subtitle.isEmpty ? null : subtitle,
          actions: [
            PoderStamp(glance: card.poder),
          ],
          bottom: card.deleted
              ? null
              : Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          if (card.isCoOwnerOnly &&
                              (card.coOwnerFolderId ?? '').isNotEmpty) {
                            final exp = card.coOwnerExpedienteId;
                            context.go(
                              exp == null || exp.isEmpty
                                  ? '/clientes/${card.coOwnerFolderId}/carpeta'
                                  : '/clientes/${card.coOwnerFolderId}/carpeta?exp=$exp',
                            );
                            return;
                          }
                          context.go(
                            '/clientes/${widget.clienteId}/carpeta',
                          );
                        },
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: Text(
                          card.isCoOwnerOnly
                              ? 'clients.openOwnerFolder'.tr(
                                  namedArgs: {
                                    'owner': card.coOwnerFolderNombre ?? '',
                                  },
                                )
                              : 'clients.openFolder'.tr(),
                        ),
                      ),
                    ),
                    if (messagingOn) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.go(
                            '/clientes/${widget.clienteId}/mensaje',
                          ),
                          icon: const Icon(Icons.mail_outline, size: 18),
                          label: Text('clients.writeEmail'.tr()),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  /// Jednou za návštěvu karty, ne po každém uložení (to by nafouklo open).
  void _logOpenOnce(AuthSnapshot? auth) {
    final tenantId = auth?.currentTenantId;
    if (tenantId == null || _openLoggedFor == widget.clienteId) return;
    _openLoggedFor = widget.clienteId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await auditClienteOpen(clienteId: widget.clienteId, tenantId: tenantId);
      if (mounted) {
        ref.invalidate(clienteAuditProvider(widget.clienteId));
      }
    });
  }

  Widget _identityCard(ClienteCard card) {
    final nie = card.nie?.trim();
    return ClienteCardSection(
      title: 'clients.identity'.tr(),
      trailing: nie != null && nie.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.accentSoft,
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              ),
              child: Text(
                '${'fields.nie'.tr()} $nie',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClienteCardFieldPair(
            left: AppTextField(label: 'clients.name'.tr(), controller: _nombre),
            right: AppTextField(label: 'fields.nie'.tr(), controller: _nie),
          ),
          const SizedBox(height: 12),
          ClienteCardFieldPair(
            left: AppTextField(
              label: 'fields.email'.tr(),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
            ),
            right: AppTextField(
              label: 'fields.tel'.tr(),
              controller: _tel,
              keyboardType: TextInputType.phone,
            ),
          ),
          const SizedBox(height: 12),
          AppTextField(label: 'fields.iban'.tr(), controller: _iban),
          const SizedBox(height: 12),
          ClienteLocaleMenu(
            value: _locale,
            onChanged: (v) => setState(() => _locale = v),
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: 'clients.notes'.tr(),
            controller: _notas,
            minLines: 2,
            maxLines: 4,
            alignLabelWithHint: true,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                value: card.status == 'activo',
                onChanged: _busy
                    ? null
                    : (on) => _status(on ? 'activo' : 'inactivo'),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  card.status == 'inactivo'
                      ? 'clients.statusInactivo'.tr()
                      : 'clients.status'.tr(),
                ),
              ),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text('clients.save'.tr()),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const ColoredBox(
            color: AppTheme.rule,
            child: SizedBox(height: 1, width: double.infinity),
          ),
          const SizedBox(height: 8),
          if (canManageLegalHold(
            ref.watch(authControllerProvider).valueOrNull ??
                const AuthSnapshot(),
          ))
            _retentionActions(card),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _softDelete,
              icon: const Icon(Icons.visibility_off_outlined, size: 18),
              label: Text('clients.softDelete'.tr()),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'clients.softDeleteHint'.tr(),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.pencil),
          ),
        ],
      ),
    );
  }

  Widget _documentsCard(ClienteCard card) {
    final types = <String>[];
    for (final t in clienteCardDocTypes) {
      if (card.documents.any((d) => d.tipo == t)) types.add(t);
    }
    for (final d in card.documents) {
      if (!types.contains(d.tipo)) types.add(d.tipo);
    }
    final trash = trashVisibleOnCard(card.hiddenDocuments);
    return ClienteCardSection(
      title: 'clients.documents'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tipo in clienteCardDocTypes)
                OfficeAttachButton(
                  outlined: true,
                  enabled: !_busy,
                  label: 'docs.$tipo'.tr(),
                  onPicked: (file) => _attachPicked(tipo, file),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (card.documents.isEmpty)
            Text(
              'clients.documentsEmpty'.tr(),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.pencil),
            )
          else
            for (var t = 0; t < types.length; t++) ...[
              if (t > 0) const SizedBox(height: 8),
              Text(
                'docs.${types[t]}'.tr(),
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: AppTheme.pencil),
              ),
              const SizedBox(height: 6),
              for (final doc in card.documents.where(
                (d) => d.tipo == types[t],
              )) ...[_cardDocumentTile(card, doc), const SizedBox(height: 8)],
            ],
          if (canPurgeDocumento(
                ref.watch(authControllerProvider).valueOrNull ??
                    const AuthSnapshot(),
              ) &&
              trash.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'folder.trash'.tr(),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppTheme.pencil),
            ),
            const SizedBox(height: 4),
            Text(
              'folder.trashHint'.tr(),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.pencil),
            ),
            const SizedBox(height: 8),
            PreviewThenHistory(
              itemCount: trash.length,
              expandLabel: 'common.history'.tr(),
              collapseLabel: 'common.historyHide'.tr(),
              builder: (context, i) => _hiddenDocumentTile(trash[i]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _contactsCard(ClienteCard card) {
    return ClienteCardSection(
      title: 'clients.contactTitle'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (card.contacts.isEmpty)
            Text(
              'clients.contactEmpty'.tr(),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.pencil),
            )
          else
            for (var i = 0; i < card.contacts.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              ClienteCardInsetRow(
                title: card.contacts[i].nombre,
                subtitle: [
                  if (card.contacts[i].relacion != null)
                    card.contacts[i].relacion!,
                  'lang.${card.contacts[i].locale}'.tr(),
                  if (card.contacts[i].tel != null) card.contacts[i].tel!,
                  if (card.contacts[i].email != null) card.contacts[i].email!,
                ].join(' · '),
                trailing: IconButton(
                  tooltip: 'clients.contactRemove'.tr(),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy
                      ? null
                      : () => _removeContact(card.contacts[i].id),
                ),
              ),
            ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _addContact,
                  child: Text('clients.contactAdd'.tr()),
                ),
                if (canCopyChannelFromContacts(
                  cardEmail: card.email,
                  cardTel: card.tel,
                  cardLocale: card.locale,
                  contacts: [
                    for (final c in card.contacts)
                      (email: c.email, tel: c.tel, locale: c.locale),
                  ],
                ))
                  FilledButton(
                    onPressed: _busy ? null : _copyChannelFromContact,
                    child: Text('clients.reachCopy'.tr()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _expedientesCard() {
    final rows = ref.watch(clienteExpedientesProvider(widget.clienteId));
    final auth = ref.watch(authControllerProvider).valueOrNull;
    final canDelete = auth != null && canSoftDeleteExpediente(auth);
    return ClienteCardSection(
      title: 'expedientes.title'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          rows.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, st) => Text('expedientes.loadError'.tr()),
            data: (list) {
              if (list.isEmpty) {
                return Text(
                  'expedientes.empty'.tr(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.pencil),
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    ClienteCardInsetRow(
                      title: 'expedientes.tipo.${list[i].tipo}'.tr(),
                      subtitle: [
                        'expedientes.estado.${list[i].estado}'.tr(),
                        if (list[i].inmuebleDireccion != null)
                          list[i].inmuebleDireccion!,
                      ].join(' · '),
                      onTap: () {
                        if (list[i].tipo == 'compraventa') {
                          context.go(
                            '/clientes/${widget.clienteId}/carpeta?exp=${list[i].id}',
                          );
                        } else {
                          context.go('/expedientes/${list[i].id}');
                        }
                      },
                      trailing: list[i].tipo == 'compraventa' || !canDelete
                          ? const Icon(Icons.chevron_right)
                          : IconButton(
                              tooltip: 'expedientes.softDelete'.tr(),
                              icon: const Icon(Icons.delete_outline),
                              onPressed: _busy
                                  ? null
                                  : () => _softDeleteExpediente(list[i].id),
                            ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FeatureGate(
                module: GestoriaModule.carpetaInmueble,
                child: OutlinedButton(
                  onPressed: _busy ? null : _newPurchase,
                  child: Text('expedientes.newPurchase'.tr()),
                ),
              ),
              FeatureGate(
                module: GestoriaModule.impuestos,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _openThin('impuestos_210'),
                      child: Text('expedientes.open210'.tr()),
                    ),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _openThin('impuestos_renta'),
                      child: Text('expedientes.openRenta'.tr()),
                    ),
                  ],
                ),
              ),
              FeatureGate(
                module: GestoriaModule.niePoder,
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _openThin('nie_tramite'),
                  child: Text('expedientes.openNie'.tr()),
                ),
              ),
              FeatureGate(
                module: GestoriaModule.policia,
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _openThin('policia'),
                  child: Text('expedientes.openPolicia'.tr()),
                ),
              ),
              FeatureGate(
                module: GestoriaModule.ayuntamiento,
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _openThin('ayuntamiento'),
                  child: Text('expedientes.openAyuntamiento'.tr()),
                ),
              ),
              FeatureGate(
                module: GestoriaModule.testament,
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _openThin('testament'),
                  child: Text('expedientes.openTestament'.tr()),
                ),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _addManualPlazo,
                child: Text('inbox.addManual'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _addManualPlazo() async {
    final list =
        ref.read(clienteExpedientesProvider(widget.clienteId)).valueOrNull ??
        [];
    if (list.isEmpty) {
      _toast('inbox.noExpediente'.tr());
      return;
    }
    final note = TextEditingController();
    var expId = list.first.id;
    var due = calendarDay(DateTime.now());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text('inbox.addManual'.tr()),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: expId,
                      decoration: InputDecoration(
                        labelText: 'inbox.manualExpediente'.tr(),
                      ),
                      items: [
                        for (final e in list)
                          DropdownMenuItem(
                            value: e.id,
                            child: Text(
                              [
                                'expedientes.tipo.${e.tipo}'.tr(),
                                if (e.inmuebleDireccion != null)
                                  e.inmuebleDireccion!,
                              ].join(' · '),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() => expId = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: note,
                      decoration: InputDecoration(
                        labelText: 'inbox.manualNote'.tr(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: due,
                            firstDate: DateTime(due.year - 1),
                            lastDate: DateTime(due.year + 5),
                          );
                          if (d == null) return;
                          setLocal(() => due = calendarDay(d));
                        },
                        child: Text(
                          '${'inbox.manualDue'.tr()}: ${inboxFechaIso(due)}',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('clients.cancel'.tr()),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('inbox.addManual'.tr()),
                ),
              ],
            );
          },
        );
      },
    );
    final text = note.text.trim();
    note.dispose();
    if (ok != true || !mounted) return;
    if (text.isEmpty) {
      _toast('inbox.noteRequired'.tr());
      return;
    }
    setState(() => _busy = true);
    try {
      await addManualPlazo(expedienteId: expId, dueOn: due, note: text);
      ref.invalidate(inboxFeedProvider);
      if (mounted) _toast('inbox.manualSaved'.tr());
    } on Object {
      if (mounted) _toast('inbox.manualError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newPurchase() async {
    final dir = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('expedientes.newPurchase'.tr()),
        content: TextField(
          controller: dir,
          autofocus: true,
          decoration: InputDecoration(labelText: 'fields.address'.tr()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('clients.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('expedientes.newPurchase'.tr()),
          ),
        ],
      ),
    );
    final address = dir.text.trim();
    dir.dispose();
    if (ok != true || !mounted) return;
    if (address.isEmpty) {
      _toast('clients.addressRequired'.tr());
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await addInmuebleCompraventa(
        clienteId: widget.clienteId,
        direccion: address,
      );
      ref.invalidate(clienteExpedientesProvider(widget.clienteId));
      if (mounted) {
        context.go('/clientes/${widget.clienteId}/carpeta?exp=$id');
      }
    } on Object {
      if (mounted) _toast('clients.saveError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _softDeleteExpediente(String expedienteId) async {
    final tenantId = ref
        .read(authControllerProvider)
        .valueOrNull
        ?.currentTenantId;
    if (tenantId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('expedientes.softDelete'.tr()),
        content: Text('expedientes.softDeleteConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('clients.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('expedientes.softDelete'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await hideThinExpediente(tenantId: tenantId, expedienteId: expedienteId);
      ref.invalidate(clienteExpedientesProvider(widget.clienteId));
    } on Object {
      if (mounted) _toast('expedientes.asistenteNoDelete'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openThin(String tipo) async {
    final kind = thinKindByTipo(tipo);
    final tenantId = ref
        .read(authControllerProvider)
        .valueOrNull
        ?.currentTenantId;
    if (kind == null || tenantId == null) return;
    setState(() => _busy = true);
    try {
      final id = await openThinExpediente(
        tenantId: tenantId,
        clienteId: widget.clienteId,
        kind: kind,
      );
      ref.invalidate(clienteExpedientesProvider(widget.clienteId));
      if (mounted) context.go('/expedientes/$id');
    } on Object {
      if (mounted) _toast('expedientes.openError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _scheduleExtracts(ClienteCard card) {
    final drafts =
        ref.read(liveAiDraftsProvider(card.id)).valueOrNull ?? const [];
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      for (final doc in card.documents) {
        if (doc.extracted.isNotEmpty) continue;
        if (drafts.any((d) => d.storagePath == doc.storagePath)) continue;
        if (!_extractStarted.add(doc.id)) continue;
        try {
          await ref
              .read(clienteCardProvider(card.id).notifier)
              .extractDocument(doc);
        } on Object {
          _extractStarted.remove(doc.id);
        }
      }
    });
  }

  Widget _cardDocumentTile(ClienteCard card, ClienteDocumento doc) {
    final drafts =
        ref.watch(liveAiDraftsProvider(card.id)).valueOrNull ?? const [];
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
      clienteNombre: card.nombre,
      clienteNie: card.nie,
    );
    final keys = fieldsForDocTipo(doc.tipo);
    final shown = [
      for (final k in keys)
        if ((values[k] ?? '').trim().isNotEmpty) k,
    ];
    final nombre = (values['fields.nombre'] ?? '').trim();
    final mismatch = nombre.isNotEmpty &&
        !documentFitsCliente(
          cardName: card.nombre,
          cardNie: card.nie,
          fields: values,
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: pending != null ? AppTheme.proposal : AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.rule),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClienteCardInsetRow(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: doc.originalName.isEmpty
                  ? 'docs.${doc.tipo}'.tr()
                  : doc.originalName,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: doc.storagePurged
                        ? 'folder.purged'.tr()
                        : 'folder.original'.tr(),
                    icon: const Icon(Icons.open_in_new),
                    onPressed: doc.storagePurged
                        ? null
                        : () => _openDoc(doc),
                  ),
                  if (canManageLegalHold(
                        ref.watch(authControllerProvider).valueOrNull ??
                            const AuthSnapshot(),
                      ) &&
                      !doc.storagePurged)
                    IconButton(
                      tooltip: card.documentoHoldActive(
                        doc.id,
                        DateTime.now(),
                      )
                          ? 'clients.legalHoldActive'.tr(
                              namedArgs: {
                                'date': legalHoldUntilIso(
                                  card.clienteHoldUntil ??
                                      defaultLegalHoldUntil(DateTime.now()),
                                ),
                              },
                            )
                          : 'clients.legalHoldDoc'.tr(),
                      icon: Icon(
                        card.documentoHoldActive(doc.id, DateTime.now())
                            ? Icons.lock
                            : Icons.lock_outline,
                      ),
                      onPressed: _busy
                          ? null
                          : () => _addHold(documentoId: doc.id),
                    ),
                  SoftRemoveIconButton(
                    tooltip: 'folder.remove'.tr(),
                    onPressed: _busy ? null : () => _removeDoc(doc.id),
                  ),
                ],
              ),
            ),
            if (mismatch)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  'folder.nameMismatch'.tr(
                    namedArgs: {'doc': nombre, 'card': card.nombre},
                  ),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (isExtractPending(values) ||
                (shown.isEmpty &&
                    pending == null &&
                    _extractStarted.contains(doc.id)))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  'ai.readingDoc'.tr(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else if (isExtractFailed(values))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  'folder.extractError'.tr(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else if (shown.isEmpty && pending == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  'folder.transcriptEmpty'.tr(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else if (shown.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Text(
                  'folder.transcript'.tr(),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            for (final k in shown)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text('${k.tr()}: ${values[k]}')),
                    if (k == 'fields.expiry')
                      _docExpiryBadge(
                        raw: (doc.extracted['fields.expiry'] ?? '').trim(),
                      ),
                  ],
                ),
              ),
            if (showDocumentoBodyOnPaper(
              hasShownFields: shown.isNotEmpty,
              bodyText: doc.bodyText,
            ))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  '${'folder.bodyText'.tr()}: ${doc.bodyText!.trim()}',
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (doc.storagePurged)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text('folder.purged'.tr()),
              ),
            if (pending != null &&
                !isExtractPending(values) &&
                !isExtractFailed(values))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final draft = pending!;
                            setState(() => _busy = true);
                            try {
                              await ref
                                  .read(
                                    clienteCardProvider(
                                      widget.clienteId,
                                    ).notifier,
                                  )
                                  .saveDocumentExtracted(
                                    documentId: doc.id,
                                    fields: draft.fields,
                                  );
                              await discardAiDraft(draft.draftId);
                              ref.read(aiPrefillProvider.notifier).state = null;
                              ref.invalidate(
                                liveAiDraftsProvider(widget.clienteId),
                              );
                              invalidateExtractQueue(ref);
                              final notice = applyExtractNotice(
                                mismatch: mismatch,
                                skippedDeedParties: false,
                              );
                              if (notice != null && mounted) {
                                _toast(notice.tr());
                              }
                            } on Object {
                              if (mounted) _toast('clients.saveError'.tr());
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                    child: Text('ai.apply'.tr()),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Badge z uloženého přepisu. OCR odpad ≠ červená. Lhůta = poder_warn_days.
  Widget _docExpiryBadge({required String raw}) {
    if (raw.isEmpty) return const SizedBox.shrink();
    final warnDays =
        ref.watch(officeSettingsProvider).valueOrNull?.poderWarnDays ?? 60;
    final tone = expiryTone(
      raw: raw,
      today: DateTime.now(),
      warnDays: warnDays,
    );
    if (tone == null) return const SizedBox.shrink();
    final (label, fill, ink) = switch (tone) {
      ExpiryTone.valid => (
        'clients.docValid'.tr(),
        AppTheme.statusOkSoft,
        AppTheme.statusOk,
      ),
      ExpiryTone.expiring => (
        'clients.docExpiring'.tr(),
        AppTheme.statusWarnSoft,
        AppTheme.statusWarn,
      ),
      ExpiryTone.expired => (
        'clients.docExpired'.tr(),
        AppTheme.statusAlertSoft,
        AppTheme.statusAlert,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
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
      ),
    );
  }

  Future<void> _attachPicked(String tipo, PickedOfficeFile file) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(clienteCardProvider(widget.clienteId).notifier)
          .attachDocument(
            tipo: tipo,
            bytes: file.bytes,
            originalName: file.name,
          );
      ref.invalidate(liveAiDraftsProvider(widget.clienteId));
      invalidateExtractQueue(ref);
    } on Object catch (e) {
      if (mounted) showOfficeUploadFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDoc(ClienteDocumento doc) async {
    if (doc.storagePurged) {
      _toast('folder.purged'.tr());
      return;
    }
    try {
      final url = await ref
          .read(clienteCardProvider(widget.clienteId).notifier)
          .signedUrl(doc.storagePath);
      if (url == null) throw StateError('url');
      final tenantId = ref
          .read(authControllerProvider)
          .valueOrNull
          ?.currentTenantId;
      if (tenantId != null) {
        await auditDocumentoOpen(
          documentId: doc.id,
          tenantId: tenantId,
          tipo: doc.tipo,
          originalName: doc.originalName,
        );
        if (mounted) {
          ref.invalidate(clienteAuditProvider(widget.clienteId));
        }
      }
      await launchUrl(Uri.parse(url));
    } on Object {
      if (mounted) _toast('folder.openError'.tr());
    }
  }

  Future<void> _removeDoc(String documentId) async {
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
    setState(() => _busy = true);
    try {
      await ref
          .read(clienteCardProvider(widget.clienteId).notifier)
          .removeDocument(documentId);
    } on Object {
      if (mounted) _toast('folder.removeError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _hiddenDocumentTile(ClienteDocumento doc) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.rule),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClienteCardInsetRow(
              leading: const Icon(Icons.delete_outline),
              title: doc.originalName.isEmpty
                  ? 'docs.${doc.tipo}'.tr()
                  : doc.originalName,
              subtitle: doc.fromDesk
                  ? 'folder.trashFromDesk'.tr(
                      namedArgs: {'doc': 'docs.${doc.tipo}'.tr()},
                    )
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => _restoreDoc(doc.id),
                    child: Text('folder.restore'.tr()),
                  ),
                  if (canManageLegalHold(
                        ref.watch(authControllerProvider).valueOrNull ??
                            const AuthSnapshot(),
                      ) &&
                      !doc.storagePurged)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _addHold(documentoId: doc.id),
                      child: Text('clients.legalHoldDoc'.tr()),
                    ),
                  TextButton(
                    onPressed: _busy || doc.storagePurged
                        ? null
                        : () => _purgeDoc(doc),
                    child: Text('folder.purge'.tr()),
                  ),
                ],
              ),
            ),
            if (doc.storagePurged)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text('folder.purged'.tr()),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreDoc(String documentId) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(clienteCardProvider(widget.clienteId).notifier)
          .restoreDocument(documentId);
    } on Object {
      if (mounted) _toast('folder.removeError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _purgeDoc(ClienteDocumento doc) async {
    final legal = documentoPurgeWarnTypes.contains(doc.tipo);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('folder.purge'.tr()),
        content: Text(
          [
            'folder.purgeConfirm'.tr(),
            if (legal) 'folder.purgeWarnLegal'.tr(),
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('clients.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('folder.purge'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(clienteCardProvider(widget.clienteId).notifier)
          .purgeDocumentStorage(doc.id);
    } on Object catch (e) {
      if (mounted) {
        _toast(
          looksLikeLegalHoldError(e)
              ? 'folder.legalHold'.tr()
              : 'folder.purgeError'.tr(),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addHold({String? documentoId}) async {
    final picked = await promptLegalHold(context);
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(clienteCardProvider(widget.clienteId).notifier).addLegalHold(
            until: picked.until,
            reason: picked.reason,
            documentoId: documentoId,
          );
    } on Object {
      if (mounted) _toast('clients.holdSaveError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _releaseHold(String holdId) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(clienteCardProvider(widget.clienteId).notifier)
          .releaseLegalHold(holdId);
    } on Object {
      if (mounted) _toast('clients.holdSaveError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _anonymize(ClienteCard card) async {
    final today = DateTime.now();
    if (card.erasureRequested) {
      _toast('clients.anonymizeDone'.tr());
      return;
    }
    if (card.clienteHoldActive(today) ||
        card.holds.any(
          (h) => legalHoldBlocks(until: h.until, today: today),
        )) {
      _toast('clients.anonymizeBlocked'.tr());
      return;
    }
    final typed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('clients.anonymize'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('clients.anonymizeConfirm'.tr()),
            const SizedBox(height: 12),
            AppTextField(
              controller: typed,
              label: 'clients.anonymize'.tr(),
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
            child: Text('clients.anonymize'.tr()),
          ),
        ],
      ),
    );
    final confirm = typed.text.trim().toUpperCase();
    typed.dispose();
    if (ok != true || confirm != 'ANON' || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(clienteCardProvider(widget.clienteId).notifier)
          .anonymizeCliente();
      if (mounted) context.go('/clientes');
    } on Object catch (e) {
      if (mounted) {
        _toast(
          looksLikeLegalHoldError(e)
              ? 'clients.anonymizeBlocked'.tr()
              : 'clients.anonymizeError'.tr(),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _retentionActions(ClienteCard card) {
    final today = DateTime.now();
    final held = card.clienteHoldActive(today);
    final until = card.clienteHoldUntil;
    ClienteHold? live;
    for (final h in card.holds) {
      if ((h.documentoId ?? '').isNotEmpty) continue;
      if (legalHoldBlocks(until: h.until, today: today)) {
        live = h;
        break;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (held && until != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'clients.legalHoldActive'.tr(
                namedArgs: {'date': legalHoldUntilIso(until)},
              ),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _addHold(),
              icon: const Icon(Icons.lock_outline, size: 18),
              label: Text('clients.legalHoldAdd'.tr()),
            ),
            if (live != null)
              OutlinedButton(
                onPressed: _busy ? null : () => _releaseHold(live!.id),
                child: Text('clients.legalHoldRelease'.tr()),
              ),
            OutlinedButton.icon(
              onPressed: _busy || card.erasureRequested
                  ? null
                  : () => _anonymize(card),
              icon: const Icon(Icons.person_off_outlined, size: 18),
              label: Text('clients.anonymize'.tr()),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'clients.anonymizeHint'.tr(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.pencil,
              ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _save() async {
    final name = _nombre.text.trim();
    if (name.isEmpty) {
      _toast('clients.nameRequired'.tr());
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(clienteCardProvider(widget.clienteId).notifier)
          .save(
            nombre: name,
            locale: _locale,
            nie: _nie.text,
            email: _email.text,
            tel: _tel.text,
            iban: _iban.text,
            notas: _notas.text,
          );
      if (!mounted) return;
      if (saved.nieConflict) {
        _nie.text = saved.keepNie;
        _toast(
          'folder.nieTaken'.tr(namedArgs: {'nie': saved.typedNie}),
        );
        return;
      }
      _toast('clients.saved'.tr());
    } on Object {
      if (mounted) _toast('clients.saveError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _status(String status) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(clienteCardProvider(widget.clienteId).notifier)
          .setStatus(status);
    } on Object {
      if (mounted) _toast('clients.saveError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _softDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('clients.softDelete'.tr()),
        content: Text('clients.softDeleteConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('clients.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('clients.softDelete'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(clienteCardProvider(widget.clienteId).notifier)
          .softDelete();
      if (mounted) context.go('/clientes');
    } on Object {
      if (mounted) _toast('clients.saveError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      await ref.read(clienteCardProvider(widget.clienteId).notifier).restore();
      if (mounted) _toast('clients.saved'.tr());
    } on Object {
      if (mounted) _toast('clients.saveError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addContact() async {
    final nombre = TextEditingController();
    final relacion = TextEditingController();
    final tel = TextEditingController();
    final email = TextEditingController();
    var locale = _locale;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text('clients.contactAdd'.tr()),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nombre,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'clients.contactName'.tr(),
                      ),
                    ),
                    TextField(
                      controller: relacion,
                      decoration: InputDecoration(
                        labelText: 'clients.contactRelation'.tr(),
                      ),
                    ),
                    TextField(
                      controller: tel,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(labelText: 'fields.tel'.tr()),
                    ),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'fields.email'.tr(),
                      ),
                    ),
                    ClienteLocaleMenu(
                      value: locale,
                      onChanged: (v) => setLocal(() => locale = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('clients.cancel'.tr()),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('clients.contactAdd'.tr()),
                ),
              ],
            );
          },
        );
      },
    );
    final name = nombre.text.trim();
    final rel = relacion.text.trim();
    final t = tel.text.trim();
    final e = email.text.trim();
    nombre.dispose();
    relacion.dispose();
    tel.dispose();
    email.dispose();
    if (ok != true || !mounted) return;
    if (name.isEmpty) {
      _toast('clients.nameRequired'.tr());
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(clienteCardProvider(widget.clienteId).notifier)
          .addContact(
            nombre: name,
            locale: locale,
            relacion: rel,
            tel: t,
            email: e,
          );
    } on Object {
      if (mounted) _toast('clients.saveError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyChannelFromContact() async {
    setState(() => _busy = true);
    try {
      final copied = await copyChannelFromContact(widget.clienteId);
      _filledFor = '';
      ref.invalidate(clienteCardProvider(widget.clienteId));
      ref.invalidate(reachGapsCountProvider);
      ref.invalidate(reachGapsListProvider);
      ref.invalidate(inboxFeedProvider);
      if (!mounted) return;
      if (!copied.email && !copied.tel && !copied.locale) {
        _toast('clients.reachCopyNone'.tr());
        return;
      }
      _toast('clients.reachCopied'.tr());
    } on Object {
      if (mounted) _toast('clients.reachCopyError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeContact(String id) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(clienteCardProvider(widget.clienteId).notifier)
          .removeContact(id);
    } on Object {
      if (mounted) _toast('clients.saveError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
