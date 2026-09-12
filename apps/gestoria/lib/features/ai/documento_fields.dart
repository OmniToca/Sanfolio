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
        'fields.holder',
        'fields.clientNo',
        'fields.period',
        'fields.consumption',
        'fields.amount',
      ];
    case 'factura_luz':
    case 'factura_gaz':
    case 'contrato_luz':
    case 'contrato_gaz':
    case 'contrato_agua':
      return const [
        'fields.nombre',
        'fields.holder',
        'fields.cups',
        'fields.period',
        'fields.consumption',
        'fields.amount',
      ];
    case 'copia_escritura':
      return const [
        'fields.nombre',
        'fields.notary',
        'fields.date',
        'fields.protocol',
      ];
    case 'poliza_seguro':
    case 'contrato_alarma':
      return const [
        'fields.nombre',
        'fields.company',
        'fields.policy',
        'fields.expiry',
      ];
    case 'copia_poder':
      return const [
        'fields.nombre',
        'fields.attorney',
        'fields.date',
        'fields.expiry',
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

/// Hrubá shoda jména na dokladu vs. karta. Bez „opravy“ NIE.
bool namesLikelyMatch(String cardName, String documentName) {
  final a = _nameTokens(cardName);
  final b = _nameTokens(documentName);
  if (a.isEmpty || b.isEmpty) return true;
  final overlap = a.where(b.contains).length;
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
