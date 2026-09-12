import 'open_external_url_stub.dart'
    if (dart.library.html) 'open_external_url_web.dart' as impl;

/// Stejná záložka — Varianta A handoff.
void assignAppUrl(String url) => impl.assignAppUrl(url);
