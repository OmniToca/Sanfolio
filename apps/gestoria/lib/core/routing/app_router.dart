import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/forbidden_screen.dart';
import '../../features/auth/impersonation_accept_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/reset_password_screen.dart';
import '../../features/auth/payment_required_screen.dart';
import '../../features/carpeta/carpeta_screen.dart';
import '../../features/carpeta/stoh_screen.dart';
import '../../features/clientes/cliente_card_screen.dart';
import '../../features/clientes/cliente_import_screen.dart';
import '../../features/clientes/cliente_merge_screen.dart';
import '../../features/clientes/clientes_screen.dart';
import '../../features/clientes/reach_gaps_screen.dart';
import '../../features/expedientes/expediente_screen.dart';
import '../../features/inbox/inbox_screen.dart';
import '../../features/ai/extract_queue_screen.dart';
import '../../features/ofertas/office_overpay_screen.dart';
import '../../features/packs/office_pack_screens.dart';
import '../../features/provision/owing_screen.dart';
import '../../features/citas/office_citas_screen.dart';
import '../../features/mensajes/mensaje_compose_screen.dart';
import '../../features/facturacion/facturacion_screen.dart';
import '../../features/facturacion/factura_emit_screen.dart';
import '../../features/facturacion/factura_detail_screen.dart';
import '../../features/posta/posta_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shell/app_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ref.read(authRefreshProvider);
  return GoRouter(
    initialLocation: '/inbox',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final path = state.uri.path;
      final loggingIn = path == '/login';
      final resetting = path == '/reset-password';
      final accepting = path == '/impersonation/accept';
      final forbidden = path == '/forbidden';
      final payment = path == '/payment-required';

      if (accepting) return null;
      if (auth.isLoading) return null;

      final snap = auth.valueOrNull ?? AuthSnapshot.signedOut;
      // Token v URL: heslo jen dokud ještě není uložené. Zbylý `?code=`
      // po úspěchu nesmí držet formulář (druhý klik = falešná chyba).
      if ((looksLikePasswordRecovery(state.uri) || path == '/sb') &&
          (snap.passwordRecovery || !snap.signedIn)) {
        if (resetting) return null;
        final q = state.uri.hasQuery ? '?${state.uri.query}' : '';
        return '/reset-password$q';
      }

      // Odkaz z e-mailu = session, ale inbox až po novém heslu.
      if (snap.passwordRecovery) {
        return resetting ? null : '/reset-password';
      }
      if (!snap.configured) {
        return (loggingIn || resetting) ? null : '/login';
      }
      if (!snap.signedIn) {
        return (loggingIn || resetting) ? null : '/login';
      }
      if (snap.isSupport &&
          !snap.impersonating &&
          snap.memberships.isEmpty) {
        return forbidden ? null : '/forbidden';
      }
      if (snap.licenceBlocked && !snap.isSupport) {
        return payment ? null : '/payment-required';
      }
      if (loggingIn || forbidden || resetting) return '/inbox';
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
        path: '/reset-password',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: ResetPasswordScreen(),
        ),
      ),
      GoRoute(
        path: '/impersonation/accept',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: ImpersonationAcceptScreen(),
        ),
      ),
      GoRoute(
        path: '/forbidden',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: ForbiddenScreen(),
        ),
      ),
      GoRoute(
        path: '/payment-required',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: PaymentRequiredScreen(),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/inbox',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: InboxScreen(),
            ),
          ),
          GoRoute(
            path: '/prepis',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ExtractQueueScreen(),
            ),
          ),
          GoRoute(
            path: '/preplatek',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: OverpayScreen(),
            ),
          ),
          GoRoute(
            path: '/dluh',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: OwingScreen(),
            ),
          ),
          GoRoute(
            path: '/citas',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: OfficeCitasScreen(),
            ),
          ),
          GoRoute(
            path: '/kanal',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ReachGapsScreen(),
            ),
          ),
          GoRoute(
            path: '/kampane',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: OfficePacksScreen(),
            ),
          ),
          GoRoute(
            path: '/sezona-210',
            redirect: (context, state) => '/kampane',
          ),
          GoRoute(
            path: '/po-notari',
            redirect: (context, state) => '/kampane',
          ),
          GoRoute(
            path: '/posta/:id',
            pageBuilder: (context, state) => NoTransitionPage(
              child: PostaScreen(
                initialId: state.pathParameters['id'],
              ),
            ),
          ),
          GoRoute(
            path: '/posta',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: PostaScreen(),
            ),
          ),
          GoRoute(
            path: '/clientes',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ClientesScreen(),
            ),
          ),
          GoRoute(
            path: '/clientes/import',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ClienteImportScreen(),
            ),
          ),
          GoRoute(
            path: '/clientes/sloucit',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ClienteMergeScreen(),
            ),
          ),
          GoRoute(
            path: '/clientes/:id/stoh',
            pageBuilder: (context, state) => NoTransitionPage(
              child: StohScreen(
                clienteId: state.pathParameters['id']!,
                expedienteId: state.uri.queryParameters['exp'],
                afterCreate: state.uri.queryParameters['new'] == '1',
              ),
            ),
          ),
          GoRoute(
            path: '/clientes/:id/carpeta/:bloque',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BloqueScreen(
                clienteId: state.pathParameters['id']!,
                bloqueKey: state.pathParameters['bloque']!,
                expedienteId: state.uri.queryParameters['exp'],
              ),
            ),
          ),
          GoRoute(
            path: '/clientes/:id/carpeta',
            pageBuilder: (context, state) => NoTransitionPage(
              child: CarpetaScreen(
                clienteId: state.pathParameters['id']!,
                expedienteId: state.uri.queryParameters['exp'],
              ),
            ),
          ),
          GoRoute(
            path: '/clientes/:id/mensaje',
            pageBuilder: (context, state) => NoTransitionPage(
              child: MensajeComposeScreen(
                clienteId: state.pathParameters['id']!,
                templateKey: state.uri.queryParameters['tpl'],
                bloqueKey: state.uri.queryParameters['bloque'],
                fecha: state.uri.queryParameters['fecha'],
                documento: state.uri.queryParameters['documento'],
                inmueble: state.uri.queryParameters['inmueble'],
                postaMessageId: state.uri.queryParameters['posta'],
              ),
            ),
          ),
          GoRoute(
            path: '/clientes/:id',
            pageBuilder: (context, state) => NoTransitionPage(
              child: ClienteCardScreen(
                clienteId: state.pathParameters['id']!,
              ),
            ),
          ),
          GoRoute(
            path: '/expedientes/:id',
            pageBuilder: (context, state) => NoTransitionPage(
              child: ExpedienteScreen(
                expedienteId: state.pathParameters['id']!,
              ),
            ),
          ),
          GoRoute(
            path: '/facturacion/nueva',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: FacturaEmitScreen(),
            ),
          ),
          GoRoute(
            path: '/facturacion/f/:id',
            pageBuilder: (context, state) => NoTransitionPage(
              child: FacturaDetailScreen(
                facturaId: state.pathParameters['id']!,
              ),
            ),
          ),
          GoRoute(
            path: '/facturacion/:libro',
            pageBuilder: (context, state) => NoTransitionPage(
              child: FacturacionScreen(
                libroKey: state.pathParameters['libro'] ?? 'emitidas',
              ),
            ),
          ),
          GoRoute(
            path: '/facturacion',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: FacturacionScreen(),
            ),
          ),
          GoRoute(
            path: '/settings/:section',
            pageBuilder: (context, state) => NoTransitionPage(
              child: SettingsScreen(
                sectionKey: state.pathParameters['section'],
              ),
            ),
          ),
          GoRoute(
            path: '/settings',
            redirect: (context, state) => '/settings/office',
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) {
      if (looksLikePasswordRecovery(state.uri) || state.uri.path == '/sb') {
        return const ResetPasswordScreen();
      }
      return Scaffold(
        body: Center(child: Text('error.notFound'.tr())),
      );
    },
  );
});
