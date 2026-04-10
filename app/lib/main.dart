import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/ble/ble_presence_service.dart';
import 'core/di/injection.dart';
import 'core/notifications/notification_service.dart';
import 'core/observer/bloc_observer.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await initDependencies();
  Bloc.observer = AppBlocObserver();

  // Initialize local notifications
  await sl<NotificationService>().init();

  // Restore BLE presence advertising if previously enabled
  sl<BlePresenceService>().restoreState();

  runApp(const AksabotApp());
}

class AksabotApp extends StatelessWidget {
  const AksabotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AuthBloc>()..add(const CheckAuthStatus()),
      child: Builder(
        builder: (context) {
          final authBloc = context.read<AuthBloc>();
          final router = createRouter(authBloc);

          return MaterialApp.router(
            title: 'Aksabot',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.system,
            routerConfig: router,
          );
        },
      ),
    );
  }
}
