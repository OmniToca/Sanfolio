import 'package:flutter/foundation.dart';

/// Cross-app URL. Release nesmí cílit na localhost (OmniToca lekce).
/// Handoff ale **vždy** nese refresh_token v hash, i na dvou localhost portech.
abstract final class PortalUrls {
  static String gestoriaAppBase() {
    return _requirePublicOrDebug(
      const String.fromEnvironment(
        'GESTORIA_BASE_URL',
        defaultValue: 'http://localhost:5555',
      ),
      name: 'GESTORIA_BASE_URL',
      debugFallback: 'http://localhost:5555',
    );
  }

  static String supportAppBase() {
    return _requirePublicOrDebug(
      const String.fromEnvironment(
        'SUPPORT_APP_URL',
        defaultValue: 'http://localhost:5556',
      ),
      name: 'SUPPORT_APP_URL',
      debugFallback: 'http://localhost:5556',
    );
  }

  /// PKCE `code` musí zůstat v query originu, ne za hashem Flutter routeru.
  static String gestoriaPasswordResetRedirect() => gestoriaAppBase();

  /// Token je v fragmentu, ne v query — nepadá do access logů. Bez tokenu
  /// druhá origin nemá JWT (pád OmniToca).
  static Uri gestoriaImpersonationAccept({
    required String sessionId,
    required String refreshToken,
  }) {
    final base = Uri.parse(gestoriaAppBase());
    final accept = base.resolve('impersonation/accept');
    final fragment = Uri(queryParameters: {'refresh_token': refreshToken}).query;
    return accept.replace(
      queryParameters: {'session_id': sessionId},
      fragment: fragment,
    );
  }

  static String _requirePublicOrDebug(
    String raw, {
    required String name,
    required String debugFallback,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isNotEmpty) {
      final base = _normalizeBaseUrl(trimmed);
      if (kReleaseMode && _isLoopback(base)) {
        throw StateError('$name must be a public URL in release (got loopback).');
      }
      return base;
    }
    if (kReleaseMode) {
      throw StateError('$name is required in release builds.');
    }
    return _normalizeBaseUrl(debugFallback);
  }

  static String normalizeBaseUrl(String raw) => _normalizeBaseUrl(raw);

  static String _normalizeBaseUrl(String raw) {
    var s = raw.trim();
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    return s;
  }

  static bool _isLoopback(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }
}
