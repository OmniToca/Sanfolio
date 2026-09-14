/// Vnitřní knihy modulu facturacion. Nová agenda sem, ne do levého railu.
///
/// PROČ: MyÚčto má Prodej/Nákup v horním menu. Sanfolio nechá rail úzký
/// (Dnes / Klienti / Faktury / Nastavení) a knihy skládá tady.
class FacturacionLibro {
  const FacturacionLibro({
    required this.key,
    required this.group,
    required this.direccion,
    this.implemented = true,
  });

  /// `emitidas` / `recibidas`. Další: presupuestos, recurrentes, proveedores.
  final String key;

  /// `ventas` = vydané strana. `compras` = přijaté.
  final String group;

  /// Sloupec `facturas.direccion`, nebo prázdné u knihy mimo tabulku.
  final String direccion;
  final bool implemented;

  bool get isVentas => group == 'ventas';
  bool get isCompras => group == 'compras';
}

const kFacturacionLibros = [
  FacturacionLibro(
    key: 'emitidas',
    group: 'ventas',
    direccion: 'emitida',
  ),
  FacturacionLibro(
    key: 'recibidas',
    group: 'compras',
    direccion: 'recibida',
  ),
];

FacturacionLibro? facturacionLibroByKey(String key) {
  for (final libro in kFacturacionLibros) {
    if (libro.key == key && libro.implemented) return libro;
  }
  return null;
}

List<String> facturacionGroups() {
  final seen = <String>{};
  return [
    for (final libro in kFacturacionLibros)
      if (libro.implemented && seen.add(libro.group)) libro.group,
  ];
}

List<FacturacionLibro> facturacionLibrosIn(String group) {
  return [
    for (final libro in kFacturacionLibros)
      if (libro.implemented && libro.group == group) libro,
  ];
}
