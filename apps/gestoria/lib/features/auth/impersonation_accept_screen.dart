import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

/// Public routa. Guard sem nesmí poslat na /login dřív, než se přečte hash.
class ImpersonationAcceptScreen extends ConsumerStatefulWidget {
  const ImpersonationAcceptScreen({super.key});

  @override
  ConsumerState<ImpersonationAcceptScreen> createState() =>
      _ImpersonationAcceptScreenState();
}

class _ImpersonationAcceptScreenState
    extends ConsumerState<ImpersonationAcceptScreen> {
  var _started = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _accept());
  }

  Future<void> _accept() async {
    if (_started) return;
    _started = true;
    try {
      final uri = GoRouterState.of(context).uri;
      final sessionId = SessionHandoff.sessionIdFromUri(uri);
      final handoffCode = SessionHandoff.handoffCodeFromUri(uri);
      final legacyRefresh = SessionHandoff.refreshTokenFromUri(uri);
      if (sessionId == null) {
        setState(() => _error = 'impersonation.missingSession'.tr());
        return;
      }
      final client = trySupabaseClient();
      if (client == null) {
        setState(() => _error = 'auth.notConfigured'.tr());
        return;
      }
      if (client.auth.currentSession == null) {
        String? refresh = legacyRefresh;
        if (refresh == null && handoffCode != null) {
          try {
            refresh = await SessionHandoff.redeemHandoffCode(
              client: client,
              sessionId: sessionId,
              code: handoffCode,
            );
          } on Object {
            setState(() => _error = 'impersonation.handoffFailed'.tr());
            return;
          }
        }
        if (refresh == null) {
          // OmniToca tady šla tiše na /login. My to řekneme.
          setState(() => _error = 'impersonation.missingToken'.tr());
          return;
        }
        await SessionHandoff.establish(client.auth, refresh);
      }
      ref.invalidate(authControllerProvider);
      final snap = await ref.read(authControllerProvider.future);
      if (!mounted) return;
      if (!snap.isSupport) {
        context.go('/forbidden');
        return;
      }
      if (snap.impersonation == null) {
        setState(() => _error = 'impersonation.sessionClosed'.tr());
        return;
      }
      context.go('/inbox');
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!),
          ),
        ),
      );
    }
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('impersonation.accepting'.tr()),
          ],
        ),
      ),
    );
  }
}
