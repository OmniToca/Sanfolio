/// Pole formuláře podle typu dokladu. AI je jen navrhne, gestor uloží.
List<String> fieldsForDocTipo(String tipo) {
  switch (tipo) {
    case 'pasaporte':
    case 'dni_nie':
      return const [
        'fields.nombre',
        'fields.docNumber',
        'fields.issued',
        'fields.expiry',
        'fields.nie',
      ];
    case 'factura_agua':
    case 'recibo_agua':
      return const [
        'fields.nombre',
        'fields.company',
        'fields.holder',
        'fields.clientNo',
        'fields.contractNo',
        'fields.invoiceNo',
        'fields.issued',
        'fields.periodFrom',
        'fields.periodTo',
        'fields.consumption',
        'fields.amount',
      ];
    case 'factura_recibida':
      return const [
        'fields.company',
        'fields.supplierNif',
        'fields.holder',
        'fields.invoiceNo',
        'fields.issued',
        'fields.due',
        'fields.concept',
        'fields.base',
        'fields.iva',
        'fields.ivaRate',
        'fields.amount',
      ];
    case 'factura_luz':
    case 'factura_gaz':
      return const [
        'fields.nombre',
        'fields.company',
        'fields.holder',
        'fields.cups',
        'fields.contractNo',
        'fields.invoiceNo',
        'fields.issued',
        'fields.periodFrom',
        'fields.periodTo',
        'fields.consumption',
        'fields.amount',
      ];
    case 'contrato_luz':
    case 'contrato_gaz':
      return const [
        'fields.nombre',
        'fields.company',
        'fields.holder',
        'fields.cups',
        'fields.contractNo',
      ];
    case 'contrato_agua':
      return const [
        'fields.nombre',
        'fields.company',
        'fields.holder',
        'fields.clientNo',
        'fields.contractNo',
      ];
    case 'copia_escritura':
      return const [
        'fields.nombre',
        'fields.nie',
        'fields.buyers',
        'fields.sellers',
        'fields.attorney',
        'fields.lawyer',
        'fields.notary',
        'fields.date',
        'fields.protocol',
        'fields.address',
        'fields.cadastral',
        'fields.parcela',
        'fields.registry',
        'fields.salePrice',
        'fields.referenceValue',
      ];
    case 'justificante_cita':
      return const [
        'fields.nombre',
        'fields.date',
        'fields.appointment',
      ];
    case 'recibo_ibi':
      return const [
        'fields.invoiceNo',
        'fields.issued',
        'fields.periodFrom',
        'fields.periodTo',
        'fields.amount',
        'fields.cadastral',
        'fields.address',
        'fields.sumaId',
        'fields.period',
        'fields.directDebit',
      ];
    case 'poliza_seguro':
    case 'contrato_alarma':
      return const [
        'fields.nombre',
        'fields.company',
        'fields.policy',
        'fields.expiry',
        'fields.periodFrom',
        'fields.periodTo',
        'fields.amount',
      ];
    case 'copia_poder':
      return const [
        'fields.nombre',
        'fields.attorney',
        'fields.date',
        'fields.expiry',
      ];
    case 'justificante_iban':
      return const [
        'fields.iban',
        'fields.holder',
        'fields.company',
      ];
    default:
      return const [
        'fields.nombre',
        'fields.holder',
        'fields.date',
        'fields.expiry',
      ];
  }
}

/// Název souboru má přednost před „první díra v bloku“ (facturas-5 ≠ contrato).
/// U dodávky bez slova contrato v názvu je default faktura — kancelář smlouvy často nemá.
bool looksLikeEscrituraName(String originalName) {
  return RegExp(
    r'escritur|compravent|smlouv|notari',
    caseSensitive: false,
  ).hasMatch(originalName);
}

String guessDocumentoTipo({
  required List<String> requiredDocTypes,
  required Set<String> alreadyHave,
  required String originalName,
}) {
  final name = originalName.toLowerCase();
  final looksFactura =
      RegExp(r'factura|recibo|invoice|abono').hasMatch(name);
  final looksContrato =
      RegExp(r'contrato|poliza|p[oó]liza').hasMatch(name);
  final looksEscritura = looksLikeEscrituraName(originalName);
  final hasFacturaTipo = requiredDocTypes.any(
    (x) => x.startsWith('factura') || x.startsWith('recibo'),
  );

  String? pick(bool Function(String tipo) test) {
    for (final t in requiredDocTypes) {
      if (alreadyHave.contains(t)) continue;
      if (test(t)) return t;
    }
    for (final t in requiredDocTypes) {
      if (test(t)) return t;
    }
    return null;
  }

  if (looksFactura) {
    final t = pick(
      (x) => x.startsWith('factura') || x.startsWith('recibo'),
    );
    if (t != null) return t;
  }
  if (looksEscritura) {
    final t = pick(
      (x) =>
          x == 'copia_escritura' ||
          x.contains('escritur') ||
          x == 'escritura_o_nota_simple',
    );
    if (t != null) return t;
    return 'copia_escritura';
  }
  if (looksContrato) {
    final t = pick(
      (x) => x.startsWith('contrato') || x.startsWith('poliza'),
    );
    if (t != null) return t;
  }
  if (hasFacturaTipo && !looksContrato) {
    final t = pick(
      (x) => x.startsWith('factura') || x.startsWith('recibo'),
    );
    if (t != null) return t;
  }
  for (final t in requiredDocTypes) {
    if (!alreadyHave.contains(t)) return t;
  }
  return requiredDocTypes.isNotEmpty ? requiredDocTypes.first : 'other';
}

/// Na desku jen identita bloku. Částka a období zůstanou na dokladu.
Map<String, String> promotePaperToDesk({
  required List<String> deskFieldKeys,
  required Map<String, String> desk,
  required Map<String, String> paper,
}) {
  return {
    ...desk,
    for (final key in deskFieldKeys)
      if ((paper[key] ?? '').trim().isNotEmpty) key: paper[key]!.trim(),
  };
}

/// Recibo má období a číslo účtenky. Deska SUMA chce rok, identifikaci a inkaso.
Map<String, String> alignSumaPaperToDesk(Map<String, String> paper) {
  final next = Map<String, String>.from(paper);
  if ((next['fields.period'] ?? '').trim().isEmpty) {
    for (final key in const [
      'fields.periodTo',
      'fields.issued',
      'fields.periodFrom',
      'fields.date',
    ]) {
      final year = RegExp(r'(20\d{2}|19\d{2})').firstMatch(next[key] ?? '');
      if (year != null) {
        next['fields.period'] = year.group(1)!;
        break;
      }
    }
  }
  if ((next['fields.sumaId'] ?? '').trim().isEmpty) {
    final clientNo = (next['fields.clientNo'] ?? '').trim();
    if (RegExp(r'^\d{4,}$').hasMatch(clientNo)) {
      next['fields.sumaId'] = clientNo;
    }
  }
  if ((next['fields.directDebit'] ?? '').trim().isEmpty) {
    final hay =
        '${next['fields.concept'] ?? ''} ${next['body_text'] ?? ''}'.toLowerCase();
    if (RegExp(r'domicili').hasMatch(hay)) {
      next['fields.directDebit'] = 'true';
    } else if (RegExp(r'aplazamiento|fraccionamiento').hasMatch(hay)) {
      next['fields.directDebit'] = 'false';
    }
  }
  return next;
}

bool isInvoiceDocTipo(String tipo) {
  return tipo.startsWith('factura') || tipo.startsWith('recibo');
}

/// Řazení stohu: nejnovější faktura nahoře. Smlouva bez data až dolů.
String paperSortStamp(Map<String, String> extracted) {
  for (final key in const [
    'fields.periodTo',
    'fields.issued',
    'fields.date',
    'fields.periodFrom',
  ]) {
    final v = (extracted[key] ?? '').trim();
    if (v.isNotEmpty) return v;
  }
  return '';
}

/// Hrubá shoda jména na dokladu vs. karta. Jedno slovo (Petr) nestačí k přepisu NIE.
bool namesLikelyMatch(String cardName, String documentName) {
  final a = _nameTokens(cardName);
  final b = _nameTokens(documentName);
  if (a.isEmpty || b.isEmpty) return false;
  final overlap = a.where(b.contains).length;
  if (a.length >= 2) return overlap >= 2;
  return overlap >= 1;
}

Set<String> _nameTokens(String raw) {
  return raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-záéíóúüñčďěňřšťžý\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.length >= 2)
      .toSet();
}
