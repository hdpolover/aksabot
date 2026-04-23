import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import '../ble/ble_presence_service.dart';
import '../network/api_client.dart';
import '../network/connectivity_service.dart';
import '../notifications/notification_service.dart';
import '../theme/theme_controller.dart';
import '../../features/auth/data/datasources/auth_remote_datasource.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/devices/data/datasources/devices_remote_datasource.dart';
import '../../features/devices/data/repositories/devices_repository_impl.dart';
import '../../features/devices/domain/repositories/devices_repository.dart';
import '../../features/devices/presentation/bloc/devices_bloc.dart';
import '../../features/conversations/data/datasources/conversations_remote_datasource.dart';
import '../../features/conversations/data/repositories/conversations_repository_impl.dart';
import '../../features/conversations/domain/repositories/conversations_repository.dart';
import '../../features/conversations/presentation/bloc/conversations_bloc.dart';
import '../../features/memories/data/datasources/memories_remote_datasource.dart';
import '../../features/memories/data/repositories/memories_repository_impl.dart';
import '../../features/memories/domain/repositories/memories_repository.dart';
import '../../features/memories/presentation/bloc/memories_bloc.dart';
import '../../features/scheduler/data/datasources/scheduler_remote_datasource.dart';
import '../../features/scheduler/data/repositories/scheduler_repository_impl.dart';
import '../../features/scheduler/domain/repositories/scheduler_repository.dart';
import '../../features/scheduler/presentation/bloc/scheduler_bloc.dart';
import '../../features/firmware/data/datasources/firmware_remote_datasource.dart';
import '../../features/firmware/data/repositories/firmware_repository_impl.dart';
import '../../features/firmware/domain/repositories/firmware_repository.dart';
import '../../features/firmware/presentation/bloc/firmware_bloc.dart';
import '../../features/devices/data/repositories/vision_repository.dart';
import '../../features/devices/presentation/bloc/vision_bloc.dart';

final sl = GetIt.instance;

Future<void> initDependencies() async {
  // Core
  const storage = FlutterSecureStorage();
  sl.registerLazySingleton<FlutterSecureStorage>(() => storage);
  sl.registerLazySingleton<ApiClient>(() => ApiClient(sl()));
  sl.registerLazySingleton<BlePresenceService>(() => BlePresenceService());
  sl.registerLazySingleton<ConnectivityService>(() => ConnectivityService());
  sl.registerLazySingleton<ThemeController>(() => ThemeController());
  sl.registerLazySingleton<NotificationService>(() => NotificationService());

  // Auth
  sl.registerLazySingleton<AuthRemoteDatasource>(
    () => AuthRemoteDatasource(sl()),
  );
  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(sl(), sl()),
  );
  sl.registerFactory(() => AuthBloc(sl()));

  // Devices
  sl.registerLazySingleton<DevicesRemoteDatasource>(
    () => DevicesRemoteDatasource(sl()),
  );
  sl.registerLazySingleton<DevicesRepository>(
    () => DevicesRepositoryImpl(sl()),
  );
  sl.registerFactory(() => DevicesBloc(sl()));

  // Conversations
  sl.registerLazySingleton<ConversationsRemoteDatasource>(
    () => ConversationsRemoteDatasource(sl()),
  );
  sl.registerLazySingleton<ConversationsRepository>(
    () => ConversationsRepositoryImpl(sl()),
  );
  sl.registerFactory(() => ConversationsBloc(sl()));

  // Memories
  sl.registerLazySingleton<MemoriesRemoteDatasource>(
    () => MemoriesRemoteDatasource(sl()),
  );
  sl.registerLazySingleton<MemoriesRepository>(
    () => MemoriesRepositoryImpl(sl()),
  );
  sl.registerFactory(() => MemoriesBloc(sl()));

  // Scheduler
  sl.registerLazySingleton<SchedulerRemoteDatasource>(
    () => SchedulerRemoteDatasource(sl()),
  );
  sl.registerLazySingleton<SchedulerRepository>(
    () => SchedulerRepositoryImpl(sl()),
  );
  sl.registerFactory(() => SchedulerBloc(sl()));

  // Firmware
  sl.registerLazySingleton<FirmwareRemoteDatasource>(
    () => FirmwareRemoteDatasource(sl()),
  );
  sl.registerLazySingleton<FirmwareRepository>(
    () => FirmwareRepositoryImpl(sl()),
  );
  sl.registerFactory(() => FirmwareBloc(sl()));

  // Vision
  sl.registerLazySingleton<VisionRepository>(
    () => VisionRepository(dio: sl<ApiClient>().dio),
  );
  sl.registerFactory(() => VisionBloc(repository: sl<VisionRepository>()));
}
