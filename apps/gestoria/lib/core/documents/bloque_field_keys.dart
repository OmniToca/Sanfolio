/// Canonical klíče desky (`fields.*`). Staré SQL šablony měly `proveedor` / `compania`.
const bloqueFieldAliases = <String, List<String>>{
  'fields.company': ['proveedor', 'compania'],
  'fields.expiry': ['fecha_vencimiento'],
  'fields.policy': ['numero_poliza'],
  'fields.contractNo': ['numero_contrato'],
  'fields.holder': ['titular'],
  'fields.clientNo': ['numero_cliente'],
  'fields.notary': ['notario'],
  'fields.date': ['escritura_fecha', 'fecha'],
  'fields.protocol': ['protocolo'],
  'fields.admin': ['proveedor'],
  'fields.sumaId': ['identificacion_suma'],
};

/// Čte pole bloku i z historického klíče, ať office-wide dotaz nelže.
String? bloqueField(Map<String, String> fields, String canonical) {
  final direct = fields[canonical]?.trim();
  if (direct != null && direct.isNotEmpty) return direct;
  for (final alias in bloqueFieldAliases[canonical] ?? const <String>[]) {
    final v = fields[alias]?.trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

/// Typy, u kterých vysypání originálu nejde vzít zpět bez varování.
const documentoPurgeWarnTypes = {
  'copia_escritura',
  'escritura_o_nota_simple',
  'recibo_ibi',
  'declaracion_plusvalia',
  'certificado_catastral',
};
