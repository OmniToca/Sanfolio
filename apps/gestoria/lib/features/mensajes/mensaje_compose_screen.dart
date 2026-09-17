import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/modules/feature_gate.dart';
import '../../core/modules/module_catalog.dart';
import '../posta/posta_address.dart';
import '../posta/posta_providers.dart';
import '../posta/posta_timeline.dart';
import '../settings/office_settings_controller.dart';
import 'mensaje_providers.dart';
import 'mensaje_templates.dart';

/// Gestor píše španělsky. Odeslání je klik člověka, ne AI.
class MensajeComposeScreen extends ConsumerStatefulWidget {
  const MensajeComposeScreen({
    super.key,
    required this.clienteId,
    this.templateKey,
    this.bloqueKey,
    this.fecha,
    this.documento,
    this.inmueble,
    this.postaMessageId,
  });

  final String clienteId;
  final String? templateKey;
  final String? bloqueKey;
  final String? fecha;
  final String? documento;
  final String? inmueble;
  final String? postaMessageId;

  @override
  ConsumerState<MensajeComposeScreen> createState() =>
      _MensajeComposeScreenState();
}

class _MensajeComposeScreenState extends ConsumerState<MensajeComposeScreen> {
  final _asunto = TextEditingController();
  final _cuerpo = TextEditingController();
  var _busy = false;
  var _applied = false;
  late String? _tpl;

  @override
  void initState() {
    super.initState();
    _tpl = widget.templateKey;
  }

  @override
  void dispose() {
    _asunto.dispose();
    _cuerpo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cliente = ref.watch(mensajeClienteProvider(widget.clienteId));
    return FeatureGate(
      module: GestoriaModule.messaging,
      fallback: Scaffold(
        appBar: AppBar(title: Text('messages.title'.tr())),
        body: Center(child: Text('messages.moduleOff'.tr())),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text('messages.title'.tr()),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/clientes/${widget.clienteId}/carpeta'),
          ),
        ),
        body: cliente.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('messages.loadError'.tr())),
          data: (row) {
            if (row == null) {
              return Center(child: Text('messages.loadError'.tr()));
            }
            if (!_applied) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _applyOnce(row, force: true);
              });
            }
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(row.nombre.isEmpty ? 'inbox.unnamed'.tr() : row.nombre),
                const SizedBox(height: 8),
                Text('messages.intro'.tr()),
                const SizedBox(height: 12),
                _ReplyToHint(),
                const SizedBox(height: 16),
                DropdownMenu<String>(
                  key: ValueKey(_tpl ?? 'none'),
                  initialSelection: _tpl,
                  label: Text('messages.template'.tr()),
                  expandedInsets: EdgeInsets.zero,
                  dropdownMenuEntries: [
                    for (final t in mensajeTemplates)
                      DropdownMenuEntry(
                        value: t.key,
                        label: 'messages.tpl.${t.key}'.tr(),
                      ),
                  ],
                  onSelected: (v) {
                    if (v == null) return;
                    setState(() {
                      _tpl = v;
                      _applied = false;
                    });
                    _applyOnce(row, force: true);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _asunto,
                  decoration: InputDecoration(
                    labelText: 'messages.subject'.tr(),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _cuerpo,
                  minLines: 8,
                  maxLines: 16,
                  decoration: InputDecoration(
                    labelText: 'messages.body'.tr(),
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : () => _email(row),
                  child: Text('messages.sendEmail'.tr()),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : () => _whatsapp(row),
                  child: Text('messages.copyWhatsapp'.tr()),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => context.go('/clientes/${widget.clienteId}/carpeta'),
                  child: Text('messages.discard'.tr()),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<String> _outbound(MensajeCliente row, String original) {
    final send = ref.read(officeSettingsProvider).valueOrNull
            ?.sendTranslatedOutbound ??
        true;
    return translateOutbound(
      text: original,
      targetLocale: row.locale,
      sendTranslated: send,
    );
  }

  void _applyOnce(MensajeCliente row, {bool force = false}) {
    if (_applied && !force) return;
    _applied = true;
    final key = _tpl ?? widget.templateKey;
    if (key == null || key.isEmpty) return;
    _tpl = key;
    final office =
        ref.read(officeSettingsProvider).valueOrNull?.displayName ?? '';
    final bloqueKey = widget.bloqueKey ?? '';
    final filled = filledTemplate(
      key: key,
      vars: {
        'nombre': row.nombre.isEmpty ? 'cliente' : row.nombre,
        'bloque': bloqueKey.isEmpty ? '—' : 'blocks.$bloqueKey'.tr(),
        'documento': _documentoLabel(widget.documento),
        'fecha': widget.fecha ?? '—',
        'despacho': office.isEmpty ? '—' : office,
        'inmueble': (widget.inmueble ?? '').trim().isEmpty
            ? '—'
            : widget.inmueble!.trim(),
        'campos_faltantes': '—',
      },
    );
    _asunto.text = filled.asunto;
    _cuerpo.text = filled.cuerpo;
  }

  Future<void> _email(MensajeCliente row) async {
    final cuerpo = _cuerpo.text.trim();
    if (cuerpo.isEmpty) {
      _toast('messages.bodyRequired'.tr());
      return;
    }
    if (row.email == null) {
      _toast('messages.noEmail'.tr());
      return;
    }
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    if (tenantId == null) return;
    final outbound = await _outbound(row, cuerpo);
    setState(() => _busy = true);
    try {
      final sent = await sendClientMessage(
        tenantId: tenantId,
        clienteId: row.id,
        asunto: _asunto.text.trim(),
        cuerpoOriginal: cuerpo,
        outboundBody: outbound,
        outboundLocale: row.locale,
        templateKey: _tpl,
        postaMessageId: widget.postaMessageId,
      );
      if (sent.ok) {
        if (!mounted) return;
        _goAfterSend();
        return;
      }
      if (!sent.notConfigured) {
        if (mounted) _toast('messages.sendError'.tr());
        return;
      }
      await recordMensaje(
        tenantId: tenantId,
        clienteId: row.id,
        canal: 'email',
        asunto: _asunto.text.trim(),
        cuerpoOriginal: cuerpo,
        localeOriginal: 'es',
        outboundLocale: row.locale,
        outboundBody: outbound,
        status: 'sent',
        templateKey: _tpl,
      );
      final office = ref.read(officeSettingsProvider).valueOrNull;
      final replyTo = postaClientReplyTo(office?.officeEmail ?? '');
      final signed = withOfficeSignature(
        outbound,
        officeEmailSignature(
          displayName: office?.displayName ?? '',
          phone: office?.officePhone ?? '',
          email: office?.officeEmail ?? '',
          nif: office?.emisorNif ?? '',
        ),
      );
      final uri = Uri(
        scheme: 'mailto',
        path: row.email,
        queryParameters: {
          'subject': _asunto.text.trim(),
          'body': signed,
          if (replyTo != null && replyTo.isNotEmpty) 'reply-to': replyTo,
        },
      );
      await launchUrl(uri);
      if (mounted) {
        _toast('messages.sendFallbackGmail'.tr());
        _goAfterSend();
      }
    } on Object {
      if (mounted) _toast('messages.sendError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goAfterSend() {
    ref.invalidate(clienteMensajesProvider(widget.clienteId));
    ref.invalidate(clienteMailTimelineProvider(widget.clienteId));
    ref.invalidate(clientePostaProvider);
    final postaId = widget.postaMessageId;
    if (postaId != null && postaId.isNotEmpty) {
      context.go('/posta/$postaId');
      return;
    }
    context.go('/clientes/${widget.clienteId}/carpeta');
  }

  Future<void> _whatsapp(MensajeCliente row) async {
    final cuerpo = _cuerpo.text.trim();
    if (cuerpo.isEmpty) {
      _toast('messages.bodyRequired'.tr());
      return;
    }
    final tenantId =
        ref.read(authControllerProvider).valueOrNull?.currentTenantId;
    if (tenantId == null) return;
    final outbound = await _outbound(row, cuerpo);
    setState(() => _busy = true);
    try {
      await recordMensaje(
        tenantId: tenantId,
        clienteId: row.id,
        canal: 'whatsapp',
        asunto: _asunto.text.trim(),
        cuerpoOriginal: cuerpo,
        localeOriginal: 'es',
        outboundLocale: row.locale,
        outboundBody: outbound,
        status: 'sent',
        templateKey: _tpl,
      );
      await Clipboard.setData(ClipboardData(text: outbound));
      if (mounted) _toast('messages.copied'.tr());
    } on Object {
      if (mounted) _toast('messages.sendError'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

/// Reply-To je schránka kanceláře. Ingest plus-adresa sem nepatří.
class _ReplyToHint extends ConsumerWidget {
  const _ReplyToHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final office =
        ref.watch(officeSettingsProvider).valueOrNull?.officeEmail ?? '';
    final addr = postaClientReplyTo(office);
    if (addr == null) {
      return Text(
        'posta.officeEmailMissing'.tr(),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            'posta.replyToHint'.tr(namedArgs: {'email': addr}),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        IconButton(
          tooltip: 'posta.replyToCopy'.tr(),
          icon: const Icon(Icons.copy),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: addr));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('posta.replyToCopied'.tr())),
            );
          },
        ),
      ],
    );
  }
}

/// Typ dokladu jde z i18n. Název nabídky kanceláře zůstane jak je.
String _documentoLabel(String? raw) {
  final v = raw?.trim() ?? '';
  if (v.isEmpty) return '—';
  if (!v.contains(' ') && v.contains('_')) return 'docs.$v'.tr();
  return v;
}

