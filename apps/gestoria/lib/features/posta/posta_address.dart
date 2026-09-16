/// Plus-adresa složky a parsování From. Čisté stringy — UI i testy.
const kPostaUuid = r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';

/// `Name <x@y>` i holé `x@y` → lower e-mail. Jinak null.
String? extractEmailAddress(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final angle = RegExp(r'<([^>]+)>').firstMatch(trimmed);
  final candidate = (angle != null ? angle.group(1)! : trimmed).trim().toLowerCase();
  if (!candidate.contains('@') || candidate.contains(' ')) return null;
  return candidate;
}

/// Reply-To u Pedir: `jarka+{clienteId}@inbound…` z ingest adresy kanceláře.
String postaReplyTo({
  required String ingestAddress,
  required String clienteId,
}) {
  final at = ingestAddress.indexOf('@');
  if (at <= 0 || clienteId.isEmpty) return ingestAddress;
  final local = ingestAddress.substring(0, at);
  final domain = ingestAddress.substring(at + 1);
  final base = local.split('+').first;
  return '$base+$clienteId@$domain';
}

/// UUID klienta z plus-tagu. Nevalidní tag = null (nesmí spadnout).
String? postaPlusClienteId(String address) {
  final email = extractEmailAddress(address);
  if (email == null) return null;
  final local = email.split('@').first;
  final plus = local.indexOf('+');
  if (plus <= 0 || plus == local.length - 1) return null;
  final tag = local.substring(plus + 1);
  if (!RegExp(kPostaUuid).hasMatch(tag)) return null;
  return tag.toLowerCase();
}

/// Gmail hledání podle RFC Message-ID, když Edge URL nedala.
String? gmailSearchUrl(String? messageIdHeader) {
  final id = messageIdHeader?.trim() ?? '';
  if (id.isEmpty) return null;
  return 'https://mail.google.com/mail/#search/rfc822msgid:${Uri.encodeComponent(id)}';
}

/// HTTP(S) odkazy z těla mailu. Zalomení řádku uprostřed URL slepíme.
List<String> extractHttpUrls(String text) {
  var glued = text;
  for (var i = 0; i < 8; i++) {
    final next = glued.replaceAllMapped(
      RegExp(r'(https?://[^\s]+)\s*\n\s*([^\s]+)'),
      (m) => '${m[1]}${m[2]}',
    );
    if (next == glued) break;
    glued = next;
  }
  final out = <String>[];
  for (final m in RegExp(r'https?://[^\s<>"]+', caseSensitive: false)
      .allMatches(glued)) {
    var url = m.group(0)!;
    url = url.replaceFirst(RegExp(r'[),.;:]+$'), '');
    if (url.isNotEmpty && !out.contains(url)) out.add(url);
  }
  return out;
}

/// Návrh bloku desky z názvu souboru a textu mailu. Gestor potvrdí, AI neukládá.
List<String> suggestPostaBloqueKeys({
  String filename = '',
  String subject = '',
  String body = '',
}) {
  final hay = '$filename\n$subject\n$body'.toLowerCase();
  const rules = <(String key, String pattern)>[
    ('luz', r'luz|electri|elektřin|iberdrola|endesa|cups|kwh|kilovatio|edp'),
    ('agua', r'agua|voda|hidralia|aqualia|emasa|canal\s|hidr[aá]|m³|\bm3\b'),
    ('gaz', r'\bgaz\b|\bgas\b|butano|gas\s?natural'),
    ('suma', r'\bibi\b|\bsuma\b|catastral|impuesto\s+sobre\s+bienes'),
    ('plusvalia', r'plusval[ií]a'),
    ('escritura', r'escritur|notari|compravent|smlouv'),
    ('comunidad', r'comunidad|administrador|společenstv'),
    ('seguro', r'seguro|p[oó]liza|pojist'),
    ('alarma', r'alarma|alarm'),
    ('poder', r'\bpoder\b|pln[aá]\s+moc'),
  ];
  final hit = <String>[];
  for (final rule in rules) {
    if (RegExp(rule.$2).hasMatch(hay) && !hit.contains(rule.$1)) {
      hit.add(rule.$1);
    }
  }
  if (hit.isEmpty &&
      RegExp(r'factura|invoice|recibo|abono|\d{1,2}[._-]\d{1,2}[._-]\d{2,4}')
          .hasMatch(hay)) {
    hit.addAll(const ['luz', 'agua', 'gaz', 'suma']);
  }
  return hit;
}

/// Gmail potvrzení přeposílání a podobný šum — do složky nepatří.
bool isPostaNoiseMail({
  required String from,
  String? subject,
}) {
  final email = (extractEmailAddress(from) ?? from).toLowerCase();
  final s = (subject ?? '').toLowerCase();
  if (email.contains('forwarding-noreply@google.') ||
      email.contains('mailer-daemon@') ||
      email.startsWith('no-reply@google.') ||
      email.startsWith('noreply@google.')) {
    return true;
  }
  return s.contains('potvrzení přeposílání') ||
      s.contains('confirmation of forwarding') ||
      s.contains('forwarding confirmation') ||
      s.contains('confirmar el reenvío') ||
      s.contains('bestätigung der weiterleitung');
}
