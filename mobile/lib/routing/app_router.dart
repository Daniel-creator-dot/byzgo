import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/session.dart';
import '../features/admin/admin_home_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/customer/customer_shell.dart';
import '../features/rider/rider_home_screen.dart';
import '../features/owner/owner_home_screen.dart';
import '../features/vendor/vendor_home_screen.dart';
import '../models/role.dart';
import '../shared/widgets/bytz_state_panels.dart';

GoRouter createAppRouter(Session session) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: session,
    redirect: (context, state) {
      if (session.isRestoring) return null;
      final loggedIn = session.isAuthenticated;
      final onLogin = state.matchedLocation == '/login';

      if (!loggedIn) {
        return onLogin ? null : '/login';
      }

      if (onLogin) {
        return _homeForRole(session.user!.role);
      }

      final role = session.user!.role;
      final path = state.matchedLocation;
      if (path.startsWith('/customer') && role != AppRole.customer) {
        return _homeForRole(role);
      }
      if (path.startsWith('/rider') && role != AppRole.rider) {
        return _homeForRole(role);
      }
      if (path.startsWith('/vendor') && role != AppRole.vendor) {
        return _homeForRole(role);
      }
      if (path.startsWith('/admin') && role != AppRole.admin) {
        return _homeForRole(role);
      }
      if (path.startsWith('/owner') && role != AppRole.owner) {
        return _homeForRole(role);
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _fadePage(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/customer',
        pageBuilder: (context, state) => _fadePage(state, const CustomerShell()),
      ),
      GoRoute(
        path: '/rider',
        pageBuilder: (context, state) => _fadePage(state, const RiderHomeScreen()),
      ),
      GoRoute(
        path: '/vendor',
        pageBuilder: (context, state) => _fadePage(state, const VendorHomeScreen()),
      ),
      GoRoute(
        path: '/admin',
        pageBuilder: (context, state) => _fadePage(state, const AdminHomeScreen()),
      ),
      GoRoute(
        path: '/owner',
        pageBuilder: (context, state) => _fadePage(state, const OwnerHomeScreen()),
      ),
    ],
    errorBuilder: (context, state) => BytzRouteErrorScreen(
      detail: state.error?.message,
    ),
  );
}

CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: Tween<double>(begin: 0.92, end: 1).animate(curved),
        child: child,
      );
    },
  );
}

String _homeForRole(AppRole role) {
  switch (role) {
    case AppRole.customer:
      return '/customer';
    case AppRole.rider:
      return '/rider';
    case AppRole.vendor:
      return '/vendor';
    case AppRole.admin:
      return '/admin';
    case AppRole.owner:
      return '/owner';
  }
}
