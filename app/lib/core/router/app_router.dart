import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/devices/presentation/pages/devices_page.dart';
import '../../features/devices/presentation/pages/device_detail_page.dart';
import '../../features/conversations/presentation/pages/conversations_page.dart';
import '../../features/memories/presentation/pages/memories_page.dart';
import '../../features/scheduler/presentation/pages/reminders_page.dart';
import '../../features/scheduler/presentation/pages/pomodoro_page.dart';

GoRouter createRouter(AuthBloc authBloc) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: GoRouterRefreshStream(authBloc.stream),
    redirect: (context, state) {
      final authState = authBloc.state;
      final isAuth = authState is Authenticated;
      final isAuthRoute =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      if (!isAuth && !isAuthRoute) return '/login';
      if (isAuth && isAuthRoute) return '/devices';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/devices',
        builder: (context, state) => const DevicesPage(),
      ),
      GoRoute(
        path: '/devices/:deviceId',
        builder: (context, state) => DeviceDetailPage(
          deviceId: state.pathParameters['deviceId']!,
        ),
        routes: [
          GoRoute(
            path: 'conversations',
            builder: (context, state) => ConversationsPage(
              deviceId: state.pathParameters['deviceId']!,
            ),
          ),
          GoRoute(
            path: 'memories',
            builder: (context, state) => MemoriesPage(
              deviceId: state.pathParameters['deviceId']!,
            ),
          ),
          GoRoute(
            path: 'reminders',
            builder: (context, state) => RemindersPage(
              deviceId: state.pathParameters['deviceId']!,
            ),
          ),
          GoRoute(
            path: 'pomodoro',
            builder: (context, state) => PomodoroPage(
              deviceId: state.pathParameters['deviceId']!,
            ),
          ),
        ],
      ),
    ],
  );
}

/// Converts a Stream into a Listenable for GoRouter's refreshListenable.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream stream) {
    stream.listen((_) => notifyListeners());
  }
}
