import 'package:flutter/foundation.dart';

/// Cross-app URL. Release nesmí cílit na localhost (OmniToca lekce).
/// Handoff nese jednorázový `code` v hash (M6); legacy refresh_token jen fallback.
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

  /// Cíl z e-mailu. Query (`code`) musí zůstat před hashem, jinak PKCE zmizí.
  static String gestoriaPasswordResetRedirect() {
    return Uri.parse(gestoriaAppBase()).resolve('/reset-password').toString();
  }

  /// Token je v fragmentu, ne v query — nepadá do access logů.
  /// Preferuj [handoffCode]; [refreshToken] je legacy fallback.
  static Uri gestoriaImpersonationAccept({
    required String sessionId,
    String? handoffCode,
    String? refreshToken,
  }) {
    final base = Uri.parse(gestoriaAppBase());
    final accept = base.resolve('impersonation/accept');
    final code = handoffCode?.trim() ?? '';
    final refresh = refreshToken?.trim() ?? '';
    final Map<String, String> fragParams;
    if (code.isNotEmpty) {
      fragParams = {'code': code};
    } else if (refresh.isNotEmpty) {
      fragParams = {'refresh_token': refresh};
    } else {
      throw ArgumentError('handoffCode or refreshToken required');
    }
    final fragment = Uri(queryParameters: fragParams).query;
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
