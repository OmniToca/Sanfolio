import '../../core/documents/office_file_pick.dart';
import '../ai/extract_text.dart';
import 'bloque_template.dart';

/// Složka ve Storage: `{tenant}/{cliente}/stoh/…`. Ne druhá evidence kanceláře.
const kStohFolder = 'stoh';

/// Jedna dávka ze šanonu. Víc by Edge extract neusnesl najednou.
const kStohBatchMax = officeFileBatchMax;

/// Ruční popis papíru. Delší by zakryl kartu.
const kLibraryCaptionMax = 500;

/// Proč floor ne: 1/38 má být 3 %, ne 2 %. Nula totálu je 0, ne NaN.
int stohUploadPercent({required int done, required int total}) {
  if (total <= 0) return 0;
  final n = done < 0 ? 0 : (done > total ? total : done);
  return ((n * 100) / total).round().clamp(0, 100);
}

double stohUploadFraction({required int done, required int total}) {
  if (total <= 0) return 0;
  final n = done < 0 ? 0 : (done > total ? total : done);
  return n / total;
}

/// Bloky, kam stoh smí papír navrhnout. provision_factura peníze nejsou sken.
const kStohBloqueKeys = <String>{
  'cliente_snapshot',
  'escritura',
  'agua',
  'luz',
  'gaz',
  'comunidad',
  'suma',
  'plusvalia',
  'seguro',
  'alarma',
  'nie_tramite',
  'poder',
};

/// Pořadí dropdownu. Set nahoře je pro validaci.
const kStohBloqueOrder = <String>[
  'cliente_snapshot',
  'escritura',
  'agua',
  'luz',
  'gaz',
  'comunidad',
  'suma',
  'plusvalia',
  'seguro',
  'alarma',
  'nie_tramite',
  'poder',
];

/// Návrh zařazení. Prázdný blok = gestor musí vybrat. AI neukládá.
class StohProposal {
  const StohProposal({this.bloqueKey = '', this.tipo = 'other'});

  final String bloqueKey;
  final String tipo;

  bool get known => bloqueKey.isNotEmpty;
}

/// Co Guardar udělá. Zapnutí bloku je klik člověka, ne LLM.
class StohGuardarPlan {
  const StohGuardarPlan({
    required this.bloqueKey,
    required this.tipo,
    required this.enableBloque,
  });

  final String bloqueKey;
  final String tipo;
  final bool enableBloque;
}

bool isStohStoragePath(String path) {
  final parts = path.split('/');
  return parts.length >= 4 && parts[2] == kStohFolder;
}

String? normalizeStohBloqueKey(String? raw) {
  final k = (raw ?? '').trim();
  if (kStohBloqueKeys.contains(k)) return k;
  return null;
}

List<String> tiposForStohBloque(String bloqueKey) {
  if (bloqueKey == 'cliente_snapshot') {
    return const ['dni_nie', 'pasaporte', 'justificante_iban', 'other'];
  }
  if (bloqueKey == 'plusvalia') {
    return const [
      'declaracion_plusvalia',
      'certificado_catastral',
      'other',
    ];
  }
  for (final t in compraventaBloques) {
    if (t.key != bloqueKey) continue;
    if (t.requiredDocTypes.isEmpty) return const ['other'];
    return [...t.requiredDocTypes, 'other'];
  }
  return const ['other'];
}

final _stohPoderName = RegExp(r'p[oó]der|apoderad');
final _stohFacturaName = RegExp(r'factura|invoice|recibo');
final _stohEscrituraName = RegExp(r'escritur|compravent|\besc\b');

/// První strana, ne celý 40stránkový PDF — „apoderado“ v klauzuli není poder.
const kStohBodyHeadChars = 4000;

String stohBodyHead(String body) {
  final t = body.trim();
  if (t.length <= kStohBodyHeadChars) return t.toLowerCase();
  return t.substring(0, kStohBodyHeadChars).toLowerCase();
}

/// Nadpis z první strany. scan_01 nic neřekne, tahle věta ano.
String? stohDocumentTitle(String body) {
  for (final raw in body.split('\n')) {
    final line = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (line.length < 10 || line.length > 90) continue;
    if (line.startsWith('---')) continue;
    if (RegExp(r'^-\s*folio', caseSensitive: false).hasMatch(line)) continue;
    if (RegExp(
      r'^(escritura|factura|recibo|p[oó]liza|poder|dni|nie|certificaci[oó]n|valor de referenc)',
      caseSensitive: false,
    ).hasMatch(line)) {
      return line;
    }
  }
  return null;
}

StohProposal? _classifyBodyHead(String head, {required bool invoiceName}) {
  if (RegExp(
        r'escritur[ae] de p[oó]der|p[oó]der notarial|poder especial|poder general',
      ).hasMatch(head) &&
      !RegExp(r'escritur[ae] de compravent').hasMatch(head)) {
    return const StohProposal(bloqueKey: 'poder', tipo: 'copia_poder');
  }
  if (!invoiceName &&
      (RegExp(
            r'escritur[ae] de compravent|escritur[ae] de ampliaci|obra nueva|declaraci[oó]n de obra|escritur[ae] p[uú]blica',
          ).hasMatch(head) ||
          (RegExp(r'escritur[ae] de').hasMatch(head) &&
              !RegExp(r'p[oó]der').hasMatch(head)) ||
          (RegExp(r'ante m[ií]').hasMatch(head) &&
              RegExp(r'notari').hasMatch(head)))) {
    return const StohProposal(
      bloqueKey: 'escritura',
      tipo: 'copia_escritura',
    );
  }
  if (RegExp(
        r'documento nacional de identidad|n[uú]mero de identidad de extranjero|tarjeta de (residencia|identidad)',
      ).hasMatch(head) &&
      !RegExp(r'escritur').hasMatch(head)) {
    return const StohProposal(
      bloqueKey: 'cliente_snapshot',
      tipo: 'dni_nie',
    );
  }
  if (RegExp(
        r'valor de referenc|certificaci[oó]n catastral',
      ).hasMatch(head) &&
      !RegExp(r'escritur[ae] de').hasMatch(head)) {
    return const StohProposal(
      bloqueKey: 'plusvalia',
      tipo: 'certificado_catastral',
    );
  }
  if (_looksLikeIbanSheet(name: '', head: head, fields: const {})) {
    return const StohProposal(
      bloqueKey: 'cliente_snapshot',
      tipo: 'justificante_iban',
    );
  }
  return null;
}

bool _looksLikeIbanSheet({
  required String name,
  required String head,
  required Map<String, String> fields,
}) {
  if (RegExp(
    r'cta bancaria|cuenta (bancaria|agencia)|bank details',
  ).hasMatch(name)) {
    return true;
  }
  final bankish = RegExp(
    r'nombre de la cuenta|account name|beneficiary|bank details|cta bancaria|\bbic\b|swift',
  ).hasMatch(head);
  final hasIban = RegExp(r'\biban\b').hasMatch(head) ||
      looksLikeIban(fields['fields.iban'] ?? '');
  if (bankish &&
      hasIban &&
      !RegExp(r'kwh|cups|suma|hidraqua|iberdrola|factura|escritur').hasMatch(
        head,
      )) {
    return true;
  }
  return false;
}

StohProposal? _classifySupply({
  required String hay,
  required String company,
}) {
  final aguaCo = RegExp(r'hidraqua|aqualia|\bagua\b|canal de isabel');
  final luzHint = RegExp(
    r'iberdrola|endesa|holaluz|gana energ|\bkwh\b|\bluz\b|electric',
  );
  final gazHint = RegExp(r'\bgaz\b|\bgas natural\b|\bgas\b');
  final looksFactura = _stohFacturaName.hasMatch(hay);
  final looksContrato = RegExp(r'contrato').hasMatch(hay);
  if (aguaCo.hasMatch(hay) || aguaCo.hasMatch(company)) {
    return StohProposal(
      bloqueKey: 'agua',
      tipo: looksContrato && !looksFactura ? 'contrato_agua' : 'factura_agua',
    );
  }
  final looksLuz = luzHint.hasMatch(hay) || luzHint.hasMatch(company);
  final looksGaz = gazHint.hasMatch(hay) || gazHint.hasMatch(company);
  if (looksGaz && !looksLuz) {
    return StohProposal(
      bloqueKey: 'gaz',
      tipo: looksContrato && !looksFactura ? 'contrato_gaz' : 'factura_gaz',
    );
  }
  if (looksLuz) {
    return StohProposal(
      bloqueKey: 'luz',
      tipo: looksContrato && !looksFactura ? 'contrato_luz' : 'factura_luz',
    );
  }
  // CUPS mají elektřina i plyn. Samo o sobě album neuhádne.
  return null;
}

/// Obsah první strany má přednost před názvem `scan_01.pdf`.
/// Název Poder / FACTURA jen jako veto: kancelář tak soubory jmenuje schválně.
/// [office] je konsensus zařazených papírů kanceláře — až po titulku, před LLM.
StohProposal classifyStohPaper({
  required String originalName,
  String bodyText = '',
  Map<String, String> fields = const {},
  StohProposal? office,
}) {
  final name = originalName.toLowerCase();
  final head = stohBodyHead(bodyText);
  final hay = '$name\n${bodyText.toLowerCase()}';
  final company = (fields['fields.company'] ?? '').toLowerCase();
  final invoiceName = _stohFacturaName.hasMatch(name);

  if (_stohPoderName.hasMatch(name)) {
    return const StohProposal(bloqueKey: 'poder', tipo: 'copia_poder');
  }

  if (_looksLikeIbanSheet(name: name, head: head, fields: fields)) {
    return const StohProposal(
      bloqueKey: 'cliente_snapshot',
      tipo: 'justificante_iban',
    );
  }

  final fromHead = _classifyBodyHead(head, invoiceName: invoiceName);
  if (fromHead != null) return fromHead;

  if (office != null &&
      office.known &&
      !(office.bloqueKey == 'escritura' && invoiceName)) {
    return office;
  }

  final fromLlm = proposalFromExtractFields(fields);
  final llmEscrituraOnInvoice =
      fromLlm.bloqueKey == 'escritura' && invoiceName;
  final llmIdentityOnDeed = fromLlm.bloqueKey == 'cliente_snapshot' &&
      head.isNotEmpty &&
      RegExp(r'escritur|compravent|notari').hasMatch(head);
  if (fromLlm.known && !llmEscrituraOnInvoice && !llmIdentityOnDeed) {
    return fromLlm;
  }

  if (RegExp(r'pasaport|passport').hasMatch(name)) {
    return const StohProposal(
      bloqueKey: 'cliente_snapshot',
      tipo: 'pasaporte',
    );
  }
  if (RegExp(r'\bdni\b|\bnie\b').hasMatch(name) &&
      !_stohEscrituraName.hasMatch(name) &&
      !invoiceName) {
    return const StohProposal(
      bloqueKey: 'cliente_snapshot',
      tipo: 'dni_nie',
    );
  }
  if (_stohEscrituraName.hasMatch(name) && !invoiceName) {
    return const StohProposal(
      bloqueKey: 'escritura',
      tipo: 'copia_escritura',
    );
  }
  if (RegExp(r'valor de referenc').hasMatch(name)) {
    return const StohProposal(
      bloqueKey: 'plusvalia',
      tipo: 'certificado_catastral',
    );
  }

  if (RegExp(r'plusval').hasMatch(hay)) {
    return const StohProposal(
      bloqueKey: 'plusvalia',
      tipo: 'declaracion_plusvalia',
    );
  }
  if (RegExp(r'\bibi\b|recibo.?ibi|suma gesti[oó]n|identificaci[oó]n suma').hasMatch(hay) &&
      !RegExp(r'escritur|compravent').hasMatch(head)) {
    return const StohProposal(bloqueKey: 'suma', tipo: 'recibo_ibi');
  }
  if (RegExp(r'comunidad|administrador de fincas').hasMatch(hay) &&
      !RegExp(r'escritur').hasMatch(head)) {
    return const StohProposal(
      bloqueKey: 'comunidad',
      tipo: 'certificado_comunidad',
    );
  }
  if (RegExp(r'p[oó]liza|seguro').hasMatch(hay) && !invoiceName) {
    return const StohProposal(bloqueKey: 'seguro', tipo: 'poliza_seguro');
  }
  if (RegExp(r'alarma').hasMatch(hay) && !RegExp(r'escritur').hasMatch(head)) {
    return const StohProposal(bloqueKey: 'alarma', tipo: 'contrato_alarma');
  }

  return _classifySupply(hay: hay, company: company) ??
      const StohProposal();
}

StohProposal proposalFromExtractFields(Map<String, String> fields) {
  final b = normalizeStohBloqueKey(fields[kProposedBloqueKey]);
  if (b == null) return const StohProposal();
  var tipo = (fields[kProposedTipo] ?? '').trim();
  final allowed = tiposForStohBloque(b);
  if (!allowed.contains(tipo)) tipo = allowed.first;
  return StohProposal(bloqueKey: b, tipo: tipo);
}

/// Null = gestor nevybral blok. AI sem nesmí.
StohGuardarPlan? planStohGuardar({
  required String selectedBloqueKey,
  required String selectedTipo,
  required bool bloqueCurrentlyEnabled,
}) {
  final bloque = normalizeStohBloqueKey(selectedBloqueKey);
  if (bloque == null) return null;
  var tipo = selectedTipo.trim();
  final allowed = tiposForStohBloque(bloque);
  if (tipo.isEmpty || !allowed.contains(tipo)) tipo = allowed.first;
  return StohGuardarPlan(
    bloqueKey: bloque,
    tipo: tipo,
    enableBloque: !bloqueCurrentlyEnabled,
  );
}
