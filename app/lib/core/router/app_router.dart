import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/auth/presentation/pages/forgot_password_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/activity/presentation/pages/activity_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/devices/presentation/pages/add_device_page.dart';
import '../../features/devices/presentation/pages/device_detail_page.dart';
import '../../features/devices/presentation/pages/device_stats_page.dart';
import '../../features/devices/presentation/pages/presence_settings_page.dart';
import '../../features/devices/presentation/pages/display_face_page.dart';
import '../../features/devices/presentation/pages/voice_audio_page.dart';
import '../../features/devices/presentation/pages/firmware_update_page.dart';
import '../../features/devices/presentation/pages/diagnostics_page.dart';
import '../../features/devices/presentation/pages/integrations_page.dart';
import '../../features/devices/presentation/pages/motion_settings_page.dart';
import '../../features/devices/presentation/pages/device_settings_page.dart';
import '../../features/devices/presentation/pages/idle_personality_page.dart';
import '../../features/devices/presentation/pages/mobility_settings_page.dart';
import '../../features/conversations/presentation/pages/conversations_page.dart';
import '../../features/memories/presentation/pages/memories_page.dart';
import '../../features/scheduler/presentation/pages/reminders_page.dart';
import '../../features/scheduler/presentation/pages/pomodoro_page.dart';
import '../../features/scheduler/presentation/pages/focus_mode_page.dart';
import 'shell_scaffold.dart';

GoRouter createRouter(AuthBloc authBloc) {
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: GoRouterRefreshStream(authBloc.stream),
    redirect: (context, state) {
      final authState = authBloc.state;
      final isAuth = authState is Authenticated;
      final isAuthRoute =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/forgot-password';

      // Still checking auth status — don't redirect yet
      if (authState is AuthInitial || authState is AuthLoading) return null;

      if (!isAuth && !isAuthRoute) return '/login';
      if (isAuth && isAuthRoute) return '/home';
      return null;
    },
    routes: [
      // Auth routes (outside shell — no nav bar)
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordPage(),
      ),

      // Main app shell — bottom nav only on these 3 root tabs
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ShellScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/activity',
                builder: (context, state) => const ActivityPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),

      // Detail routes — outside shell, NO bottom nav bar
      GoRoute(
        path: '/devices/add',
        builder: (context, state) => const AddDevicePage(),
      ),
      GoRoute(
        path: '/devices/:deviceId',
        builder: (context, state) => DeviceDetailPage(
          deviceId: state.pathParameters['deviceId']!,
        ),
        routes: _deviceSubRoutes(),
      ),
      GoRoute(
        path: '/conversations/:deviceId',
        builder: (context, state) => ConversationsPage(
          deviceId: state.pathParameters['deviceId']!,
        ),
      ),
      GoRoute(
        path: '/memories/:deviceId',
        builder: (context, state) => MemoriesPage(
          deviceId: state.pathParameters['deviceId']!,
        ),
      ),
    ],
  );
}

/// All sub-routes under /devices/:deviceId/
List<RouteBase> _deviceSubRoutes() {
  return [
    GoRoute(
      path: 'personality',
      builder: (context, state) => IdlePersonalityPage(
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
    GoRoute(
      path: 'focus',
      builder: (context, state) => FocusModePage(
        deviceId: state.pathParameters['deviceId']!,
      ),
    ),
    GoRoute(
      path: 'presence',
      builder: (context, state) => PresenceSettingsPage(
        deviceId: state.pathParameters['deviceId']!,
      ),
    ),
    GoRoute(
      path: 'settings',
      builder: (context, state) => DeviceSettingsPage(
        deviceId: state.pathParameters['deviceId']!,
      ),
    ),
    GoRoute(
      path: 'stats',
      builder: (context, state) => DeviceStatsPage(
        deviceId: state.pathParameters['deviceId']!,
      ),
    ),
    GoRoute(
      path: 'display',
      builder: (context, state) => DisplayFacePage(
        deviceId: state.pathParameters['deviceId']!,
      ),
    ),
    GoRoute(
      path: 'voice',
      builder: (context, state) => VoiceAudioPage(
        deviceId: state.pathParameters['deviceId']!,
      ),
    ),
    GoRoute(
      path: 'firmware',
      builder: (context, state) => FirmwareUpdatePage(
        deviceId: state.pathParameters['deviceId']!,
      ),
    ),
    GoRoute(
      path: 'diagnostics',
      builder: (context, state) => DiagnosticsPage(
        deviceId: state.pathParameters['deviceId']!,
      ),
    ),
    GoRoute(
      path: 'integrations',
      builder: (context, state) => IntegrationsPage(
        deviceId: state.pathParameters['deviceId']!,
      ),
    ),
    GoRoute(
      path: 'motion',
      builder: (context, state) => MotionSettingsPage(
        deviceId: state.pathParameters['deviceId']!,
      ),
    ),
    GoRoute(
      path: 'mobility',
      builder: (context, state) => MobilitySettingsPage(
        deviceId: state.pathParameters['deviceId']!,
      ),
    ),
  ];
}

/// Converts a Stream into a Listenable for GoRouter's refreshListenable.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream stream) {
    stream.listen((_) => notifyListeners());
  }
}
