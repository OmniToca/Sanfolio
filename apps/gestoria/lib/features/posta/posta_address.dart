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
