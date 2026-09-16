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

/// Kam má klient kliknout Odpovědět: schránka kanceláře, ne plus-adresa ingestu.
String? postaClientReplyTo(String officeEmail) {
  return extractEmailAddress(officeEmail);
}

/// Podpis odchozí výzvy. Jméno + telefon + e-mail + NIF, nic víc.
String officeEmailSignature({
  String displayName = '',
  String phone = '',
  String email = '',
  String nif = '',
}) {
  final addr = extractEmailAddress(email) ?? '';
  final lines = [
    displayName.trim(),
    phone.trim(),
    addr,
    nif.trim().isEmpty ? '' : 'NIF ${nif.trim()}',
  ].where((s) => s.isNotEmpty).toList();
  if (lines.isEmpty) return '';
  return '--\n${lines.join('\n')}';
}

/// Připojí podpis, pokud v těle ještě není.
String withOfficeSignature(String body, String signature) {
  final sig = signature.trim();
  if (sig.isEmpty) return body;
  final trimmed = body.trimRight();
  if (trimmed.contains(sig) || trimmed.endsWith(sig)) return trimmed;
  return '$trimmed\n\n$sig';
}

/// Doména From. Gmail/Seznam sem nepatří — tam blok pamatujeme jen na přesný e-mail.
String? postaSenderDomain(String address) {
  final email = extractEmailAddress(address) ?? address.trim().toLowerCase();
  final at = email.lastIndexOf('@');
  if (at <= 0 || at == email.length - 1) return null;
  return email.substring(at + 1);
}

const kPostaConsumerDomains = {
  'gmail.com',
  'googlemail.com',
  'outlook.com',
  'hotmail.com',
  'live.com',
  'msn.com',
  'icloud.com',
  'me.com',
  'mac.com',
  'yahoo.com',
  'yahoo.es',
  'ymail.com',
  'proton.me',
  'protonmail.com',
  'seznam.cz',
  'email.cz',
  'post.cz',
  'centrum.cz',
  'volny.cz',
};

bool isPostaConsumerDomain(String domain) =>
    kPostaConsumerDomains.contains(domain.toLowerCase());

/// Re:/Fwd: pryč, ať výzva a odpověď sedí do jednoho vlákna.
String normalizePostaSubject(String? subject) {
  var s = (subject ?? '').trim();
  final prefix = RegExp(
    r'^(re|fw|fwd|aw|sv|odp|vá)\s*:\s*',
    caseSensitive: false,
  );
  for (var i = 0; i < 6; i++) {
    final next = s.replaceFirst(prefix, '');
    if (next == s) break;
    s = next.trim();
  }
  return s.toLowerCase();
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

/// Gmail `rfc822msgid:` chce ID bez `< >`. Se závorkami hledání spadne na nulu.
String rfc822MessageId(String raw) {
  var id = raw.trim();
  if (id.startsWith('<') && id.endsWith('>') && id.length > 2) {
    id = id.substring(1, id.length - 1).trim();
  }
  return id;
}

/// Hledání v Gmailu: nejdřív Message-ID, jinak From + předmět (přeposlaná kopie).
String? gmailSearchUrl(
  String? messageIdHeader, {
  String? from,
  String? subject,
}) {
  final id = rfc822MessageId(messageIdHeader ?? '');
  if (id.contains('@')) {
    return 'https://mail.google.com/mail/#search/rfc822msgid:${Uri.encodeComponent(id)}';
  }
  final fromAddr = extractEmailAddress(from ?? '') ?? '';
  final sub = (subject ?? '').trim().replaceAll('"', '');
  if (fromAddr.isEmpty && sub.isEmpty) return null;
  final q = [
    if (fromAddr.isNotEmpty) 'from:$fromAddr',
    if (sub.isNotEmpty) 'subject:"$sub"',
  ].join(' ');
  return 'https://mail.google.com/mail/#search/${Uri.encodeComponent(q)}';
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

/// Návrh bloku desky z názvu souboru, textu a zapamatovaného odesílatele.
List<String> suggestPostaBloqueKeys({
  String filename = '',
  String subject = '',
  String body = '',
  String? rememberedKey,
}) {
  final hit = <String>[];
  final remembered = (rememberedKey ?? '').trim();
  if (remembered.isNotEmpty) hit.add(remembered);
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
