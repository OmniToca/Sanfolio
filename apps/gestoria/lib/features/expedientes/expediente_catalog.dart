import '../carpeta/bloque_template.dart';

/// Tenký spis: checklist + plazo, žádný výpočet daně.
class ThinExpedienteKind {
  const ThinExpedienteKind({
    required this.tipo,
    required this.templateKey,
    required this.moduleKey,
    required this.fieldKeys,
    required this.requiredFieldKeys,
    this.requiredDocTypes = const [],
    this.requiredDocsMode = RequiredDocsMode.all,
  });

  final String tipo;
  final String templateKey;
  final String moduleKey;
  final List<String> fieldKeys;
  final List<String> requiredFieldKeys;
  final List<String> requiredDocTypes;
  final RequiredDocsMode requiredDocsMode;

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
    fieldKeys: [
      'fields.periodicity',
      'fields.modeloPeriod',
      'fields.deadline',
      'fields.filed',
    ],
    requiredFieldKeys: [
      'fields.periodicity',
      'fields.modeloPeriod',
      'fields.deadline',
    ],
    requiredDocTypes: [
      'escritura_o_nota_simple',
      'recibo_ibi',
      'certificado_catastral',
    ],
  ),
  ThinExpedienteKind(
    tipo: 'impuestos_renta',
    templateKey: 'renta',
    moduleKey: 'impuestos',
    fieldKeys: ['fields.exercise', 'fields.deadline', 'fields.filed'],
    requiredFieldKeys: ['fields.exercise', 'fields.deadline'],
  ),
  ThinExpedienteKind(
    tipo: 'nie_tramite',
    templateKey: 'nie_tramite',
    moduleKey: 'nie_poder',
    fieldKeys: ['fields.nieStatus', 'fields.appointment', 'fields.expiry'],
    requiredFieldKeys: ['fields.nieStatus'],
  ),
  ThinExpedienteKind(
    tipo: 'policia',
    templateKey: 'policia',
    moduleKey: 'policia',
    fieldKeys: ['fields.tramiteStatus', 'fields.appointment', 'fields.notes'],
    requiredFieldKeys: ['fields.tramiteStatus'],
    requiredDocTypes: ['justificante_cita'],
  ),
  ThinExpedienteKind(
    tipo: 'ayuntamiento',
    templateKey: 'ayuntamiento',
    moduleKey: 'ayuntamiento',
    fieldKeys: ['fields.tramiteStatus', 'fields.appointment', 'fields.notes'],
    requiredFieldKeys: ['fields.tramiteStatus'],
    requiredDocTypes: ['justificante_cita'],
  ),
  ThinExpedienteKind(
    tipo: 'testament',
    templateKey: 'testament',
    moduleKey: 'testament',
    fieldKeys: ['fields.tramiteStatus', 'fields.appointment', 'fields.notes'],
    requiredFieldKeys: ['fields.tramiteStatus'],
    requiredDocTypes: ['copia_escritura', 'justificante_cita'],
    requiredDocsMode: RequiredDocsMode.any,
  ),
];

ThinExpedienteKind? thinKindByTipo(String tipo) {
  for (final k in thinExpedienteKinds) {
    if (k.tipo == tipo) return k;
  }
  return null;
}
