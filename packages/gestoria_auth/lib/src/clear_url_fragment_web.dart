import 'package:web/web.dart' as web;

void clearUrlFragment() {
  try {
    final loc = web.window.location;
    final path = loc.pathname;
    final search = loc.search;
    if (path.isEmpty) return;
    web.window.history.replaceState(null, '', '$path$search');
  } on Object {
    // Bez History API zůstane hash — redeem už spotřeboval kód.
  }
}
