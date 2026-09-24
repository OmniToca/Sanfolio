import 'clear_url_fragment_stub.dart'
    if (dart.library.js_interop) 'clear_url_fragment_web.dart' as impl;

/// Po setSession smaže hash (code / legacy refresh_token) z adresního řádku.
void clearUrlFragment() => impl.clearUrlFragment();
