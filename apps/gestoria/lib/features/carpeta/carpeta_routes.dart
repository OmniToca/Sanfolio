/// Cesty desky. Blok má vlastní URL, ať AI i tužka otevírají stejný šanon.
String carpetaRoute(
  String clienteId, {
  String? expedienteId,
  bool afterSkip = false,
}) {
  final base = '/clientes/$clienteId/carpeta';
  final q = <String>[];
  final exp = expedienteId?.trim();
  if (exp != null && exp.isNotEmpty) q.add('exp=$exp');
  if (afterSkip) q.add('skip=1');
  if (q.isEmpty) return base;
  return '$base?${q.join('&')}';
}

String carpetaStohRoute(
  String clienteId, {
  String? expedienteId,
  bool afterCreate = false,
}) {
  final q = <String>[];
  final exp = expedienteId?.trim();
  if (exp != null && exp.isNotEmpty) q.add('exp=$exp');
  if (afterCreate) q.add('new=1');
  final suffix = q.isEmpty ? '' : '?${q.join('&')}';
  return '/clientes/$clienteId/stoh$suffix';
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
