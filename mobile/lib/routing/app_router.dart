import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/session.dart';
import '../features/admin/admin_home_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/customer/customer_home_screen.dart';
import '../features/rider/rider_home_screen.dart';
import '../features/vendor/vendor_home_screen.dart';
import '../models/role.dart';

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
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/customer',
        builder: (context, state) => const CustomerHomeScreen(),
      ),
      GoRoute(
        path: '/rider',
        builder: (context, state) => const RiderHomeScreen(),
      ),
      GoRoute(
        path: '/vendor',
        builder: (context, state) => const VendorHomeScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminHomeScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text(state.error.toString())),
    ),
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
  }
}
