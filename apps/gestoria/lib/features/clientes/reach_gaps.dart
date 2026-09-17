const reachLocales = {'cs', 'en', 'es', 'de', 'fr'};

bool reachLocaleValid(String? raw) {
  return reachLocales.contains((raw ?? '').trim().toLowerCase());
}

/// Díra na kartě: bez kanálu, kanál jen u kontaktu, nebo locale.
class ReachGap {
  const ReachGap({
    required this.sinCanal,
    required this.contactOnly,
    required this.noLocale,
    required this.canCopy,
  });

  final bool sinCanal;
  final bool contactOnly;
  final bool noLocale;
  final bool canCopy;

  bool get hasGap => sinCanal || contactOnly || noLocale || canCopy;
}

ReachGap classifyReachGap({
  String? cardEmail,
  String? cardTel,
  String? cardLocale,
  String? contactEmail,
  String? contactTel,
  String? contactLocale,
}) {
  final cardMail = (cardEmail ?? '').trim().isNotEmpty;
  final cardPhone = (cardTel ?? '').trim().isNotEmpty;
  final cMail = (contactEmail ?? '').trim().isNotEmpty;
  final cPhone = (contactTel ?? '').trim().isNotEmpty;
  final noLocale = !reachLocaleValid(cardLocale);
  final canCopy = (!cardMail && cMail) ||
      (!cardPhone && cPhone) ||
      (noLocale && reachLocaleValid(contactLocale));
  return ReachGap(
    sinCanal: !cardMail && !cardPhone && !cMail && !cPhone,
    contactOnly: !cardMail && !cardPhone && (cMail || cPhone),
    noLocale: noLocale,
    canCopy: canCopy,
  );
}

/// Na kartě: aspoň jeden kontakt má co doplnit do prázdného e-mailu/tel/locale.
bool canCopyChannelFromContacts({
  String? cardEmail,
  String? cardTel,
  String? cardLocale,
  required Iterable<({String? email, String? tel, String? locale})> contacts,
}) {
  for (final c in contacts) {
    if (classifyReachGap(
      cardEmail: cardEmail,
      cardTel: cardTel,
      cardLocale: cardLocale,
      contactEmail: c.email,
      contactTel: c.tel,
      contactLocale: c.locale,
    ).canCopy) {
      return true;
    }
  }
  return false;
}

class ReachGapRow {
  const ReachGapRow({
    required this.clienteId,
    required this.clienteNombre,
    required this.gap,
    this.email,
    this.tel,
    this.locale,
    this.contactNombre,
    this.contactEmail,
    this.contactTel,
    this.contactLocale,
  });

  final String clienteId;
  final String clienteNombre;
  final String? email;
  final String? tel;
  final String? locale;
  final String? contactNombre;
  final String? contactEmail;
  final String? contactTel;
  final String? contactLocale;
  final ReachGap gap;
}

String? _opt(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

bool _flag(Object? v) => v == true;

ReachGapRow? reachGapRowFromRpc(Map raw) {
  final clienteId = '${raw['cliente_id'] ?? ''}'.trim();
  if (clienteId.isEmpty) return null;
  final gap = classifyReachGap(
    cardEmail: _opt(raw['email']),
    cardTel: _opt(raw['tel']),
    cardLocale: _opt(raw['locale']),
    contactEmail: _opt(raw['contact_email']),
    contactTel: _opt(raw['contact_tel']),
    contactLocale: _opt(raw['contact_locale']),
  );
  if (!gap.hasGap) return null;
  return ReachGapRow(
    clienteId: clienteId,
    clienteNombre: '${raw['cliente_nombre'] ?? ''}'.trim(),
    email: _opt(raw['email']),
    tel: _opt(raw['tel']),
    locale: _opt(raw['locale']),
    contactNombre: _opt(raw['contact_nombre']),
    contactEmail: _opt(raw['contact_email']),
    contactTel: _opt(raw['contact_tel']),
    contactLocale: _opt(raw['contact_locale']),
    gap: ReachGap(
      sinCanal: _flag(raw['sin_canal']) || gap.sinCanal,
      contactOnly: _flag(raw['contact_only']) || gap.contactOnly,
      noLocale: _flag(raw['no_locale']) || gap.noLocale,
      canCopy: _flag(raw['can_copy']) || gap.canCopy,
    ),
  );
}
