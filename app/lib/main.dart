import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/ble/ble_presence_service.dart';
import 'core/di/injection.dart';
import 'core/notifications/notification_service.dart';
import 'features/devices/domain/repositories/devices_repository.dart';
import 'core/observer/bloc_observer.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await initDependencies();
  Bloc.observer = AppBlocObserver();

  // Initialize local notifications
  await sl<NotificationService>().init();

  // Wire up presence reporting: when the scan service detects arrival/departure,
  // it calls the backend via the devices repository.
  final presence = sl<BlePresenceService>();
  presence.onPresenceChanged = (deviceId, event, awaySeconds) async {
    await sl<DevicesRepository>().reportPresence(
      deviceId,
      event,
      awayDurationSeconds: awaySeconds,
    );
  };

  // Restore BLE presence scanning if previously enabled
  presence.restoreState();

  runApp(const AksabotApp());
}

class AksabotApp extends StatefulWidget {
  const AksabotApp({super.key});

  @override
  State<AksabotApp> createState() => _AksabotAppState();
}

class _AksabotAppState extends State<AksabotApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Dart timers freeze when iOS suspends the app, so the retry loop inside
  /// BlePresenceService can silently die.  Every time the user foregrounds the
  /// app we kick `resumeIfNeeded()` — it's a no-op when already connected.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      sl<BlePresenceService>().resumeIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AuthBloc>()..add(const CheckAuthStatus()),
      child: Builder(
        builder: (context) {
          final authBloc = context.read<AuthBloc>();
          final router = createRouter(authBloc);

          return ValueListenableBuilder<ThemeMode>(
            valueListenable: sl<ThemeController>(),
            builder: (context, themeMode, _) {
              return MaterialApp.router(
                title: 'Aksabot',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                darkTheme: AppTheme.dark,
                themeMode: themeMode,
                routerConfig: router,
              );
            },
          );
        },
      ),
    );
  }
}
