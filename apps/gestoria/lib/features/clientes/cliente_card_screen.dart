import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/staff_role.dart';
import '../../core/i18n/app_locales.dart';
import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/presentation/widgets/app_widgets.dart';
import 'cliente_audit.dart';
import 'cliente_card_controller.dart';
import 'clientes_providers.dart';
import '../expedientes/expediente_catalog.dart';
import '../expedientes/expediente_controller.dart';
import '../inbox/inbox_providers.dart';
import '../mensajes/mensaje_history.dart';

class ClienteCardScreen extends ConsumerStatefulWidget {
  const ClienteCardScreen({super.key, required this.clienteId});

  final String clienteId;

  @override
  ConsumerState<ClienteCardScreen> createState() => _ClienteCardScreenState();
}

class _ClienteCardScreenState extends ConsumerState<ClienteCardScreen> {
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _tel = TextEditingController();
  final _iban = TextEditingController();
  final _notas = TextEditingController();
  String _locale = 'cs';
  var _filledFor = '';
  var _busy = false;
  var _openLoggedFor = '';

  @override
  void didUpdateWidget(ClienteCardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clienteId != widget.clienteId) {
      _filledFor = '';
      _openLoggedFor = '';
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
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
        return Scaffold(
          appBar: AppBar(
            title: Text(
              card.nombre.isEmpty ? 'clients.cardTitle'.tr() : card.nombre,
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/clientes'),
            ),
            actions: [
              if (!card.deleted)
                IconButton(
                  tooltip: 'clients.openFolder'.tr(),
                  icon: const Icon(Icons.folder_open),
                  onPressed: () =>
                      context.go('/clientes/${widget.clienteId}/carpeta'),
                ),
              if (!card.deleted)
                FeatureGate(
                  module: GestoriaModule.messaging,
                  child: IconButton(
                    tooltip: 'messages.title'.tr(),
                    icon: const Icon(Icons.mail_outline),
                    onPressed: () =>
                        context.go('/clientes/${widget.clienteId}/mensaje'),
                  ),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
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
                  FilledButton(
                    onPressed: _busy ? null : () => _restore(),
                    child: Text('clients.restore'.tr()),
                  ),
              ] else ...[
                if (card.nie != null && card.nie!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('${'fields.nie'.tr()}: ${card.nie}'),
                  ),
                AppTextField(
                  label: 'clients.name'.tr(),
                  controller: _nombre,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'fields.email'.tr(),
                  controller: _email,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'fields.tel'.tr(),
                  controller: _tel,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: 'fields.iban'.tr(),
                  controller: _iban,
                ),
                const SizedBox(height: 12),
                _LocaleMenu(
                  value: _locale,
                  onChanged: (v) => setState(() => _locale = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notas,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'clients.notes'.tr(),
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('clients.status'.tr()),
                  subtitle: Text(
                    card.status == 'inactivo'
                        ? 'clients.statusInactivo'.tr()
                        : 'clients.statusActivo'.tr(),
                  ),
                  value: card.status == 'activo',
                  onChanged: _busy
                      ? null
                      : (on) => _status(on ? 'activo' : 'inactivo'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text('clients.save'.tr()),
                ),
                const SizedBox(height: 24),
                Text(
                  'clients.documents'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final tipo in clienteCardDocTypes)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _attachDoc(tipo),
                        icon: const Icon(Icons.attach_file, size: 18),
                        label: Text('docs.$tipo'.tr()),
                      ),
                  ],
                ),
                if (card.documents.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: Text('clients.documentsEmpty'.tr()),
                  ),
                for (final doc in card.documents)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(
                      doc.originalName.isEmpty
                          ? 'docs.${doc.tipo}'.tr()
                          : doc.originalName,
                    ),
                    subtitle: Text('docs.${doc.tipo}'.tr()),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'folder.open'.tr(),
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () => _openDoc(doc.storagePath),
                        ),
                        IconButton(
                          tooltip: 'folder.remove'.tr(),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _busy
                              ? null
                              : () => _removeDoc(doc.id),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                ClienteMensajeHistory(
                  clienteId: widget.clienteId,
                  clientLocale: card.locale,
                ),
                const SizedBox(height: 24),
                Text(
                  'clients.contactTitle'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (card.contacts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('clients.contactEmpty'.tr()),
                  ),
                for (final c in card.contacts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: ListTile(
                        title: Text(c.nombre),
                        subtitle: Text(
                          [
                            if (c.relacion != null) c.relacion!,
                            'lang.${c.locale}'.tr(),
                            if (c.tel != null) c.tel!,
                            if (c.email != null) c.email!,
                          ].join(' · '),
                        ),
                        trailing: IconButton(
                          tooltip: 'clients.contactRemove'.tr(),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _busy
                              ? null
                              : () => _removeContact(c.id),
                        ),
                      ),
                    ),
                  ),
                OutlinedButton(
                  onPressed: _busy ? null : _addContact,
                  child: Text('clients.contactAdd'.tr()),
                ),
                const SizedBox(height: 24),
                Text(
                  'expedientes.title'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ..._expedienteSection(),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _addManualPlazo,
                  child: Text('inbox.addManual'.tr()),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: _busy ? null : _softDelete,
                  child: Text('clients.softDelete'.tr()),
                ),
              ],
              if (showAudit) ...[
                const SizedBox(height: 24),
                _ClienteAuditSection(clienteId: widget.clienteId),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Jednou za návštěvu karty, ne po každém uložení (to by nafouklo open).
  void _logOpenOnce(AuthSnapshot? auth) {
    final tenantId = auth?.currentTenantId;
    if (tenantId == null || _openLoggedFor == widget.clienteId) return;
    _openLoggedFor = widget.clienteId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await auditClienteOpen(
        clienteId: widget.clienteId,
        tenantId: tenantId,
      );
      if (mounted) {
        ref.invalidate(clienteAuditProvider(widget.clienteId));
      }
    });
  }

  List<Widget> _expedienteSection() {
    final rows = ref.watch(clienteExpedientesProvider(widget.clienteId));
    final auth = ref.watch(authControllerProvider).valueOrNull;
    final canDelete = auth != null && canSoftDeleteExpediente(auth);
    return [
      rows.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(),
        ),
        error: (e, st) => Text('expedientes.loadError'.tr()),
        data: (list) {
          if (list.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('expedientes.empty'.tr()),
            );
          }
          return Column(
            children: [
              for (final e in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    onTap: () {
                      if (e.tipo == 'compraventa') {
                        context.go(
                          '/clientes/${widget.clienteId}/carpeta?exp=${e.id}',
                        );
                      } else {
                        context.go('/expedientes/${e.id}');
                      }
                    },
                    child: ListTile(
                      title: Text('expedientes.tipo.${e.tipo}'.tr()),
                      subtitle: Text(
                        [
                          'expedientes.estado.${e.estado}'.tr(),
                          if (e.inmuebleDireccion != null) e.inmuebleDireccion!,
                        ].join(' · '),
                      ),
                      trailing: e.tipo == 'compraventa' || !canDelete
                          ? const Icon(Icons.chevron_right)
                          : IconButton(
                              tooltip: 'expedientes.softDelete'.tr(),
                              icon: const Icon(Icons.delete_outline),
                              onPressed: _busy
                                  ? null
                                  : () => _softDeleteExpediente(e.id),
                            ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      FeatureGate(
        module: GestoriaModule.carpetaInmueble,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton(
            onPressed: _busy ? null : _newPurchase,
            child: Text('expedientes.newPurchase'.tr()),
          ),
        ),
      ),
      FeatureGate(
        module: GestoriaModule.impuestos,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _busy ? null : () => _openThin('impuestos_210'),
              child: Text('expedientes.open210'.tr()),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _openThin('impuestos_renta'),
              child: Text('expedientes.openRenta'.tr()),
            ),
          ],
        ),
      ),
      FeatureGate(
        module: GestoriaModule.niePoder,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton(
            onPressed: _busy ? null : () => _openThin('nie_tramite'),
            child: Text('expedientes.openNie'.tr()),
          ),
        ),
      ),
    ];
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
      await addManualPlazo(
        expedienteId: expId,
        dueOn: due,
        note: text,
      );
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
          decoration: InputDecoration(
            labelText: 'fields.address'.tr(),
          ),
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
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
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
      await hideThinExpediente(
        tenantId: tenantId,
        expedienteId: expedienteId,
      );
      ref.invalidate(clienteExpedientesProvider(widget.clienteId));
    } on Object {
      if (mounted) _toast('expedientes.asistenteNoDelete'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openThin(String tipo) async {
    final kind = thinKindByTipo(tipo);
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
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
      if (mounted) _toast('clients.saveError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attachDoc(String tipo) async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _toast('folder.uploadError'.tr());
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(clienteCardProvider(widget.clienteId).notifier).attachDocument(
            tipo: tipo,
            bytes: bytes,
            originalName: file.name,
          );
    } on Object {
      if (mounted) _toast('folder.uploadError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDoc(String path) async {
    try {
      final url = await ref
          .read(clienteCardProvider(widget.clienteId).notifier)
          .signedUrl(path);
      if (url == null) throw StateError('url');
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

  Future<void> _save() async {
    final name = _nombre.text.trim();
    if (name.isEmpty) {
      _toast('clients.nameRequired'.tr());
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(clienteCardProvider(widget.clienteId).notifier).save(
            nombre: name,
            locale: _locale,
            email: _email.text,
            tel: _tel.text,
            iban: _iban.text,
            notas: _notas.text,
          );
      if (mounted) _toast('clients.saved'.tr());
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
                      decoration: InputDecoration(
                        labelText: 'fields.tel'.tr(),
                      ),
                    ),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'fields.email'.tr(),
                      ),
                    ),
                    _LocaleMenu(
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
      await ref.read(clienteCardProvider(widget.clienteId).notifier).addContact(
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

class _LocaleMenu extends StatelessWidget {
  const _LocaleMenu({required this.value, required this.onChanged});

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

/// Jen owner. Log se tu nedá smazat — append-only v DB.
class _ClienteAuditSection extends ConsumerWidget {
  const _ClienteAuditSection({required this.clienteId});

  final String clienteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clienteAuditProvider(clienteId));
    final when = DateFormat.yMMMd(context.locale.toString()).add_Hm();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'audit.title'.tr(),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text('audit.hint'.tr()),
        const SizedBox(height: 8),
        async.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, st) => Text('audit.loadError'.tr()),
          data: (events) {
            if (events.isEmpty) {
              return Text('audit.empty'.tr());
            }
            return Column(
              children: [
                for (final e in events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: ListTile(
                        title: Text(e.actionI18nKey.tr()),
                        subtitle: Text(
                          [
                            when.format(e.createdAt.toLocal()),
                            e.actorLabel ?? 'audit.system'.tr(),
                            if (e.impersonating) 'audit.impersonation'.tr(),
                          ].join(' · '),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
