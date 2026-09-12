/// Šablona bloku desky. Popisky jdou z i18n (`blocks.$key`, `fields.*`).
class BloqueTemplate {
  const BloqueTemplate({
    required this.key,
    required this.fieldKeys,
    this.requiredFieldKeys,
    this.requiredDocTypes = const [],
    this.moduleKey = 'carpeta_inmueble',
  });

  final String key;
  final List<String> fieldKeys;

  /// Prázdné = pole na desce jsou jen zobrazení (jméno žije na `clientes`).
  final List<String>? requiredFieldKeys;
  final List<String> requiredDocTypes;
  final String moduleKey;

  String get labelI18n => 'blocks.$key';

  List<String> get requiredKeys => requiredFieldKeys ?? fieldKeys;
}

const compraventaBloques = <BloqueTemplate>[
  BloqueTemplate(
    key: 'cliente_snapshot',
    fieldKeys: [
      'fields.nie',
      'fields.email',
      'fields.tel',
      'fields.address',
      'fields.iban',
    ],
    requiredFieldKeys: [],
  ),
  BloqueTemplate(
    key: 'escritura',
    fieldKeys: ['fields.notary', 'fields.date', 'fields.protocol'],
    requiredDocTypes: ['copia_escritura'],
  ),
  BloqueTemplate(
    key: 'agua',
    fieldKeys: [
      'fields.company',
      'fields.clientNo',
      'fields.contractNo',
      'fields.holder',
    ],
    requiredDocTypes: ['contrato_agua', 'factura_agua'],
  ),
  BloqueTemplate(
    key: 'luz',
    fieldKeys: [
      'fields.company',
      'fields.cups',
      'fields.contractNo',
      'fields.holder',
    ],
    requiredDocTypes: ['contrato_luz', 'factura_luz'],
  ),
  BloqueTemplate(
    key: 'gaz',
    fieldKeys: [
      'fields.company',
      'fields.cups',
      'fields.contractNo',
      'fields.holder',
    ],
    requiredDocTypes: ['contrato_gaz', 'factura_gaz'],
  ),
  BloqueTemplate(
    key: 'comunidad',
    fieldKeys: ['fields.admin', 'fields.reference', 'fields.holder'],
    requiredDocTypes: ['certificado_comunidad'],
  ),
  BloqueTemplate(
    key: 'suma',
    fieldKeys: ['fields.sumaId', 'fields.directDebit', 'fields.period'],
    requiredDocTypes: ['recibo_ibi'],
  ),
  BloqueTemplate(
    key: 'plusvalia',
    fieldKeys: ['fields.authority', 'fields.deadline', 'fields.filed'],
    requiredDocTypes: ['declaracion_plusvalia'],
  ),
  BloqueTemplate(
    key: 'seguro',
    fieldKeys: ['fields.company', 'fields.policy', 'fields.expiry'],
    requiredDocTypes: ['poliza_seguro'],
  ),
  BloqueTemplate(
    key: 'provision_factura',
    fieldKeys: ['fields.received', 'fields.invoiced', 'fields.remaining'],
  ),
  BloqueTemplate(
    key: 'alarma',
    fieldKeys: ['fields.company', 'fields.contractNo', 'fields.expiry'],
    requiredDocTypes: ['contrato_alarma'],
  ),
  BloqueTemplate(
    key: 'nie_tramite',
    moduleKey: 'nie_poder',
    fieldKeys: ['fields.nieStatus', 'fields.appointment', 'fields.expiry'],
  ),
  BloqueTemplate(
    key: 'poder',
    moduleKey: 'nie_poder',
    fieldKeys: ['fields.attorney', 'fields.date', 'fields.expiry'],
    requiredDocTypes: ['copia_poder'],
  ),
];
