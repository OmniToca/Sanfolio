/// Cesty desky. Blok má vlastní URL, ať AI i tužka otevírají stejný šanon.
String carpetaRoute(String clienteId, {String? expedienteId}) {
  final base = '/clientes/$clienteId/carpeta';
  final exp = expedienteId?.trim();
  if (exp == null || exp.isEmpty) return base;
  return '$base?exp=$exp';
}

String carpetaBloqueRoute(
  String clienteId,
  String bloqueKey, {
  String? expedienteId,
}) {
  final base = '/clientes/$clienteId/carpeta/$bloqueKey';
  final exp = expedienteId?.trim();
  if (exp == null || exp.isEmpty) return base;
  return '$base?exp=$exp';
}
