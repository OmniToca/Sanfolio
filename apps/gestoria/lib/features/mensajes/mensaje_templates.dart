/// Šablony výzev. Tělo je španělsky — gestor píše ES, i18n je jen výběr šablony.
class MensajeTemplate {
  const MensajeTemplate({
    required this.key,
    required this.asunto,
    required this.cuerpo,
  });

  final String key;
  final String asunto;
  final String cuerpo;
}

const mensajeTemplates = <MensajeTemplate>[
  MensajeTemplate(
    key: 'falta_documento',
    asunto: 'Documentación pendiente — {{inmueble}}',
    cuerpo: '''Hola {{nombre}},

Para seguir con su expediente nos falta: {{documento}} ({{bloque}}).
Puede responder a este correo con una foto nítida o un PDF.

Gracias,
{{despacho}}''',
  ),
  MensajeTemplate(
    key: 'faltan_datos',
    asunto: 'Datos pendientes — {{bloque}}',
    cuerpo: '''Hola {{nombre}},

Necesitamos completar {{bloque}}. En concreto: {{campos_faltantes}}.

Gracias,
{{despacho}}''',
  ),
  MensajeTemplate(
    key: 'recordatorio',
    asunto: 'Recordatorio: {{bloque}} — {{fecha}}',
    cuerpo: '''Hola {{nombre}},

Le recordamos el plazo de {{bloque}} con fecha {{fecha}}
(inmueble: {{inmueble}}).

Si ya lo tiene resuelto, ignore este mensaje o envíenos el justificante.

{{despacho}}''',
  ),
  MensajeTemplate(
    key: 'vencido',
    asunto: 'Plazo vencido — {{bloque}}',
    cuerpo: '''Hola {{nombre}},

El plazo de {{bloque}} ({{fecha}}) ya ha vencido. Contacte con nosotros
lo antes posible para evitar recargos.

{{despacho}}''',
  ),
];

MensajeTemplate? mensajeTemplateByKey(String key) {
  for (final t in mensajeTemplates) {
    if (t.key == key) return t;
  }
  return null;
}

/// Inbox kind → šablona. AI tohle nesmí odeslat.
String templateKeyForInboxKind(String itemKind) {
  return switch (itemKind) {
    'missing_document' => 'falta_documento',
    'missing_data' => 'faltan_datos',
    'overdue' => 'vencido',
    _ => 'recordatorio',
  };
}

/// Stav bloku na desce → šablona výzvy. Stejné mapování jako inbox.
String templateKeyForBloqueStatus(String status) {
  return templateKeyForInboxKind(status);
}

String fillMensajeTemplate(String source, Map<String, String> vars) {
  var out = source;
  for (final e in vars.entries) {
    out = out.replaceAll('{{${e.key}}}', e.value);
  }
  return out.replaceAll(RegExp(r'\{\{[a-z_]+\}\}'), '—');
}

MensajeTemplate filledTemplate({
  required String key,
  required Map<String, String> vars,
}) {
  final raw = mensajeTemplateByKey(key) ?? mensajeTemplates.last;
  return MensajeTemplate(
    key: raw.key,
    asunto: fillMensajeTemplate(raw.asunto, vars),
    cuerpo: fillMensajeTemplate(raw.cuerpo, vars),
  );
}
