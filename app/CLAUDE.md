# Aksabot Flutter App

Companion app for the Aksabot AI desk companion. Handles device provisioning (BLE), presence detection (BLE advertising), and device management. Communicates with the NestJS backend via REST API.

## Quick Start

```bash
flutter pub get              # Install dependencies
flutter run                  # Run on connected device/simulator
flutter test                 # Run all tests
flutter analyze              # Static analysis (zero issues target)
```

## Tech Stack

| Concern | Solution |
|---------|----------|
| State management | BLoC (`flutter_bloc: ^9.1.0`) |
| Navigation | GoRouter (`go_router: ^15.1.2`) |
| DI | GetIt (`get_it: ^8.0.3`) — manual registration |
| HTTP | Dio (`dio: ^5.8.0`) |
| Secure storage | `flutter_secure_storage` (JWT tokens) |
| BLE central | `flutter_blue_plus` (device scanning + provisioning) |
| BLE peripheral | `flutter_ble_peripheral` (presence advertising) |
| Connectivity | `connectivity_plus` (network status banner) |
| Notifications | `flutter_local_notifications` (3 channels) |
| Testing | `bloc_test` + `mocktail` |

Dart SDK: `^3.11.4`

## Project Structure

```
lib/
  core/
    ble/            — BLE constants, provisioning service, presence service
    constants/      — App-wide constants
    di/             — GetIt dependency injection (injection.dart)
    error/          — Failure types, exception handling
    local/          — Local storage utilities
    network/        — ApiClient (Dio), connectivity service
    notifications/  — Local notification service (3 channels)
    observer/       — BLoC observer for debug logging
    router/         — GoRouter config (app_router.dart)
    theme/          — ThemeController, AppTheme (Material 3)
    types/          — Custom type definitions
    utils/          — Utility functions
    widgets/        — Shared reusable widgets
  features/
    auth/           — Login, register, forgot password
    activity/       — Activity page (conversations + memories)
    conversations/  — Conversation list + detail
    devices/        — Device dashboard, add device, settings, diagnostics
    home/           — Home page with device dashboard
    memories/       — Memory list + detail
    scheduler/      — Reminders, pomodoro, focus mode
    settings/       — App settings, account
```

Each feature follows **Clean Architecture**: `data/` (repositories, models) → `domain/` (entities, use cases) → `presentation/` (pages, BLoCs, widgets).

## BLoCs

| BLoC | Scope | Key Events |
|------|-------|------------|
| `AuthBloc` | Global | Login, register, logout, refresh token, forgot password |
| `DevicesBloc` | Global | Fetch devices, add/remove device, update settings |
| `ConversationsBloc` | Per-device | Fetch conversations, search |
| `MemoriesBloc` | Per-device | Fetch memories, delete |
| `SchedulerBloc` | Per-device | Reminders config, pomodoro state, focus mode |

All registered as factories in GetIt (`core/di/injection.dart`).

## BLE Services

### Provisioning (`BleProvisioningService`)
5-step flow: scan → connect → write WiFi creds → register device + write token → name device. Uses `flutter_blue_plus` as BLE central.

GATT services: WiFi (0xFFE0), Auth (0xFFE1), Control (0xFFE2), Status (0xFFE3).

### Presence (`BlePresenceService`)
Advertises UUID 0xFFE4 as BLE peripheral in low-power background mode. ESP32 scans for this to detect user at desk.

Settings: enable/disable, RSSI threshold (-90 to -60 dBm), grace period (15-60s), silent wake (2-10 min).

Auto-restores advertising on app launch via `restoreState()` in `main.dart`.

## API Client

`core/network/api_client.dart` — Dio instance with:
- Base URL from `.env` (`API_BASE_URL`)
- JWT interceptor (auto-attaches token from secure storage)
- Refresh token interceptor (auto-refreshes on 401)
- Connectivity check before requests

## Navigation

GoRouter with `StatefulShellRoute` for 3-tab bottom nav:
- **Home** — Device dashboard, quick actions
- **Activity** — Conversations + memories with device picker
- **Settings** — Account, theme, notifications, sign out

Auth routes: `/login`, `/register`, `/forgot-password`

## Conventions

- **Zero analysis issues**: `flutter analyze` must pass clean
- **Feature isolation**: Features don't import from each other — only from `core/`
- **Error handling**: `dartz` Either type (`Either<Failure, T>`) in repositories
- **Naming**: BLoC events are past-tense verbs (`DevicesFetched`, `AuthLoginRequested`), states are nouns (`AuthAuthenticated`, `DevicesLoaded`)
- **Tests**: BLoC tests colocated in `test/features/{feature}/`, use `mocktail` for mocking

## Platform Configuration

**iOS** (`ios/Runner/Info.plist`):
- `NSBluetoothAlwaysUsageDescription`, `NSBluetoothPeripheralUsageDescription`
- `UIBackgroundModes`: `bluetooth-central`, `bluetooth-peripheral`

**Android** (`android/app/src/main/AndroidManifest.xml`):
- `BLUETOOTH_ADVERTISE`, `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`
- `ACCESS_FINE_LOCATION` (required for BLE on Android)
