import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/forbidden_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/tenants/tenant_detail_screen.dart';
import '../../features/tenants/tenants_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
    final refresh = ref.read(authRefreshProvider);
  return GoRouter(
    initialLocation: '/tenants',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final path = state.uri.path;
      final loggingIn = path == '/login';
      final forbidden = path == '/forbidden';

      if (auth.isLoading) return null;

      final snap = auth.valueOrNull ?? AuthSnapshot.signedOut;
      if (!snap.configured) {
        return loggingIn ? null : '/login';
      }
      if (!snap.signedIn) {
        return loggingIn ? null : '/login';
      }
      if (!snap.isSupport) {
        return forbidden ? null : '/forbidden';
      }
      if (loggingIn || forbidden) return '/tenants';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: LoginScreen(),
        ),
      ),
      GoRoute(
        path: '/forbidden',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: ForbiddenScreen(),
        ),
      ),
      GoRoute(
        path: '/tenants',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: TenantsScreen(),
        ),
      ),
      GoRoute(
        path: '/tenants/:id',
        pageBuilder: (context, state) => NoTransitionPage(
          child: TenantDetailScreen(tenantId: state.pathParameters['id']!),
        ),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('error.notFound'.tr())),
    ),
  );
});
