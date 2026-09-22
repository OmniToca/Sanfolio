import 'package:web/web.dart' as web;

const _key = 'sanfolio_set_password';

bool pendingSetPasswordFlag() {
  try {
    return web.window.sessionStorage.getItem(_key) == '1';
  } on Object {
    return false;
  }
}

void clearSetPasswordFlag() {
  try {
    web.window.sessionStorage.removeItem(_key);
  } on Object {
    // Bez sessionStorage pořád drží `_passwordRecovery` v paměti.
  }
}

void dropAuthLinkFromAddressBar() {
  try {
    final path = web.window.location.pathname;
    if (path.isEmpty) return;
    web.window.history.replaceState(null, '', path);
  } on Object {
    // Adresa s `code` jen znovu otevře formulář; flag to drží.
  }
}
