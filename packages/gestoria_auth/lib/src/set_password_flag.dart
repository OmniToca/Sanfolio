import 'set_password_flag_stub.dart'
    if (dart.library.html) 'set_password_flag_web.dart' as impl;

/// `index.html` ho zapíše u invite/recovery, než GoTrue spolkne URL.
bool pendingSetPasswordFlag() => impl.pendingSetPasswordFlag();

void clearSetPasswordFlag() => impl.clearSetPasswordFlag();

/// Po uložení hesla zbylý `?code=` / hash nesmí držet formulář.
void dropAuthLinkFromAddressBar() => impl.dropAuthLinkFromAddressBar();
