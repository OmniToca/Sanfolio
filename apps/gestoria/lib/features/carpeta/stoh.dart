import '../../core/documents/office_file_pick.dart';
import '../ai/extract_text.dart';
import 'bloque_template.dart';

/// Složka ve Storage: `{tenant}/{cliente}/stoh/…`. Ne druhá evidence kanceláře.
const kStohFolder = 'stoh';

/// Jedna dávka ze šanonu. Víc by Edge extract neusnesl najednou.
const kStohBatchMax = officeFileBatchMax;

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
    return const ['dni_nie', 'pasaporte', 'other'];
  }
  for (final t in compraventaBloques) {
    if (t.key != bloqueKey) continue;
    if (t.requiredDocTypes.isEmpty) return const ['other'];
    return [...t.requiredDocTypes, 'other'];
  }
  return const ['other'];
}

/// Heuristika + `proposed_*` z extract. Gestor může přepsat dropdownem.
StohProposal classifyStohPaper({
  required String originalName,
  String bodyText = '',
  Map<String, String> fields = const {},
}) {
  final fromLlm = proposalFromExtractFields(fields);
  if (fromLlm.known) return fromLlm;

  final name = originalName.toLowerCase();
  final body = bodyText.toLowerCase();
  final hay = '$name\n$body';
  final cups = (fields['fields.cups'] ?? '').trim();
  final company = (fields['fields.company'] ?? '').toLowerCase();

  if (RegExp(r'pasaport|passport').hasMatch(hay)) {
    return const StohProposal(
      bloqueKey: 'cliente_snapshot',
      tipo: 'pasaporte',
    );
  }
  if (RegExp(r'\bdni\b|\bnie\b').hasMatch(name) &&
      !RegExp(r'escritur|factura|contrato').hasMatch(name)) {
    return const StohProposal(
      bloqueKey: 'cliente_snapshot',
      tipo: 'dni_nie',
    );
  }
  if (RegExp(r'escritur|compravent|notari|protocolo').hasMatch(hay)) {
    return const StohProposal(
      bloqueKey: 'escritura',
      tipo: 'copia_escritura',
    );
  }
  if (RegExp(r'plusval').hasMatch(hay)) {
    return const StohProposal(
      bloqueKey: 'plusvalia',
      tipo: 'declaracion_plusvalia',
    );
  }
  if (RegExp(r'\bibi\b|\bsuma\b|catastral').hasMatch(hay) &&
      !RegExp(r'escritur').hasMatch(hay)) {
    return const StohProposal(bloqueKey: 'suma', tipo: 'recibo_ibi');
  }
  if (RegExp(r'comunidad|administrador de fincas').hasMatch(hay)) {
    return const StohProposal(
      bloqueKey: 'comunidad',
      tipo: 'certificado_comunidad',
    );
  }
  if (RegExp(r'p[oó]liza|seguro').hasMatch(hay) &&
      !RegExp(r'factura').hasMatch(name)) {
    return const StohProposal(bloqueKey: 'seguro', tipo: 'poliza_seguro');
  }
  if (RegExp(r'\bpoder\b|apoderad').hasMatch(hay)) {
    return const StohProposal(bloqueKey: 'poder', tipo: 'copia_poder');
  }
  if (RegExp(r'alarma').hasMatch(hay)) {
    return const StohProposal(bloqueKey: 'alarma', tipo: 'contrato_alarma');
  }

  final aguaCo = RegExp(r'hidraqua|aqualia|\bagua\b|canal de isabel');
  final luzHint = RegExp(r'iberdrola|endesa|holaluz|\bcups\b|\bkwh\b|\bluz\b');
  final gazHint = RegExp(r'\bgaz\b|\bgas natural\b|\bgas\b');
  final looksFactura = RegExp(r'factura|recibo|invoice').hasMatch(hay);
  final looksContrato = RegExp(r'contrato').hasMatch(hay);

  if (aguaCo.hasMatch(hay) || aguaCo.hasMatch(company)) {
    return StohProposal(
      bloqueKey: 'agua',
      tipo: looksContrato && !looksFactura ? 'contrato_agua' : 'factura_agua',
    );
  }
  if (cups.isNotEmpty || luzHint.hasMatch(hay) || luzHint.hasMatch(company)) {
    final gazOnly = gazHint.hasMatch(hay) &&
        !RegExp(r'\bkwh\b|\bluz\b|electric').hasMatch(hay);
    if (gazOnly) {
      return StohProposal(
        bloqueKey: 'gaz',
        tipo: looksContrato && !looksFactura ? 'contrato_gaz' : 'factura_gaz',
      );
    }
    return StohProposal(
      bloqueKey: 'luz',
      tipo: looksContrato && !looksFactura ? 'contrato_luz' : 'factura_luz',
    );
  }
  if (gazHint.hasMatch(hay) || gazHint.hasMatch(company)) {
    return StohProposal(
      bloqueKey: 'gaz',
      tipo: looksContrato && !looksFactura ? 'contrato_gaz' : 'factura_gaz',
    );
  }

  return const StohProposal();
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
