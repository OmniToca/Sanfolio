import '../carpeta/bloque_template.dart';
import 'modelo_210.dart';

/// Tenký spis: checklist + plazo. Modelo 210 počítá IRNR; AEAT nepodává.
/// Není to druhá tištěná carpeta — ale deska úkonu musí mít klienta, papíry a kontext.
class ThinExpedienteKind {
  const ThinExpedienteKind({
    required this.tipo,
    required this.templateKey,
    required this.moduleKey,
    required this.fieldKeys,
    required this.requiredFieldKeys,
    this.requiredDocTypes = const [],
    this.optionalDocTypes = const [],
    this.requiredDocsMode = RequiredDocsMode.all,
    this.linksInmueble = false,
  });

  final String tipo;
  final String templateKey;
  final String moduleKey;
  final List<String> fieldKeys;
  final List<String> requiredFieldKeys;
  final List<String> requiredDocTypes;

  /// Slot na desce, stav bloku to neřeší (DNI u 210).
  final List<String> optionalDocTypes;
  final RequiredDocsMode requiredDocsMode;

  /// 210 / magistrát / závěť patří k nemovitosti, NIE a renta k osobě.
  final bool linksInmueble;

  /// Povinné i volitelné typy, bez duplicit — UI kreslí slot na každý.
  List<String> get paperSlotTypes {
    final out = [...requiredDocTypes];
    for (final t in optionalDocTypes) {
      if (!out.contains(t)) out.add(t);
    }
    return out;
  }

  BloqueTemplate get template => BloqueTemplate(
        key: templateKey,
        fieldKeys: fieldKeys,
        requiredFieldKeys: requiredFieldKeys,
        requiredDocTypes: requiredDocTypes,
        requiredDocsMode: requiredDocsMode,
        moduleKey: moduleKey,
      );
}

const thinExpedienteKinds = <ThinExpedienteKind>[
  ThinExpedienteKind(
    tipo: 'impuestos_210',
    templateKey: 'modelo_210',
    moduleKey: 'impuestos',
    linksInmueble: true,
    fieldKeys: [
      'fields.periodicity',
      'fields.modeloPeriod',
      'fields.deadline',
      'fields.filed',
      'fields.address',
      'fields.cadastral',
      'fields.sumaId',
      'fields.receipt',
      'fields.notes',
      ...modelo210TaxInputKeys,
    ],
    requiredFieldKeys: [
      'fields.periodicity',
      'fields.modeloPeriod',
      'fields.deadline',
      'fields.incomeKind',
      'fields.taxResidency',
    ],
    requiredDocTypes: [
      'escritura_o_nota_simple',
      'recibo_ibi',
      'certificado_catastral',
    ],
    optionalDocTypes: ['dni_nie'],
  ),
  ThinExpedienteKind(
    tipo: 'impuestos_renta',
    templateKey: 'renta',
    moduleKey: 'impuestos',
    fieldKeys: [
      'fields.exercise',
      'fields.deadline',
      'fields.filed',
      'fields.receipt',
      'fields.notes',
    ],
    requiredFieldKeys: ['fields.exercise', 'fields.deadline'],
    optionalDocTypes: ['dni_nie'],
  ),
  ThinExpedienteKind(
    tipo: 'nie_tramite',
    templateKey: 'nie_tramite',
    moduleKey: 'nie_poder',
    fieldKeys: [
      'fields.nieStatus',
      'fields.appointment',
      'fields.expiry',
      'fields.notes',
    ],
    requiredFieldKeys: ['fields.nieStatus'],
    optionalDocTypes: ['dni_nie', 'pasaporte'],
  ),
  ThinExpedienteKind(
    tipo: 'policia',
    templateKey: 'policia',
    moduleKey: 'policia',
    fieldKeys: [
      'fields.tramiteStatus',
      'fields.appointment',
      'fields.authority',
      'fields.docNumber',
      'fields.notes',
    ],
    requiredFieldKeys: ['fields.tramiteStatus'],
    requiredDocTypes: ['justificante_cita'],
    optionalDocTypes: ['dni_nie'],
  ),
  ThinExpedienteKind(
    tipo: 'ayuntamiento',
    templateKey: 'ayuntamiento',
    moduleKey: 'ayuntamiento',
    linksInmueble: true,
    fieldKeys: [
      'fields.tramiteStatus',
      'fields.appointment',
      'fields.authority',
      'fields.docNumber',
      'fields.notes',
    ],
    requiredFieldKeys: ['fields.tramiteStatus'],
    requiredDocTypes: ['justificante_cita'],
    optionalDocTypes: ['dni_nie'],
  ),
  ThinExpedienteKind(
    tipo: 'testament',
    templateKey: 'testament',
    moduleKey: 'testament',
    linksInmueble: true,
    fieldKeys: [
      'fields.tramiteStatus',
      'fields.appointment',
      'fields.notary',
      'fields.date',
      'fields.notes',
    ],
    requiredFieldKeys: ['fields.tramiteStatus'],
    requiredDocTypes: ['copia_escritura', 'justificante_cita'],
    requiredDocsMode: RequiredDocsMode.any,
    optionalDocTypes: ['dni_nie'],
  ),
];

ThinExpedienteKind? thinKindByTipo(String tipo) {
  for (final k in thinExpedienteKinds) {
    if (k.tipo == tipo) return k;
  }
  return null;
}
