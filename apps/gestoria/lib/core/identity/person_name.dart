/// Jméno a příjmení na kartě. DB má `nombre` + `apellidos`; UI dřív obě slila
/// do jednoho pole a při uložení `apellidos` mazala. Jedno slovo v `nombre`
/// nestačí k párování na listině (`namesLikelyMatch` chce dvě).
({String nombre, String apellidos}) splitPersonName({
  required String nombre,
  String? apellidos,
}) {
  final given = _oneLine(nombre);
  final family = _oneLine(apellidos ?? '');
  if (family.isNotEmpty || !given.contains(' ')) {
    return (nombre: given, apellidos: family);
  }
  final i = given.indexOf(' ');
  return (
    nombre: given.substring(0, i),
    apellidos: given.substring(i + 1).trim(),
  );
}

/// Seznam, hlavička, extract hint: `Renata Sušičová`.
String joinPersonName(String nombre, String apellidos) {
  return [nombre.trim(), apellidos.trim()].where((s) => s.isNotEmpty).join(' ');
}

String _oneLine(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');
