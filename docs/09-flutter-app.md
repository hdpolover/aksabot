# 09 — Flutter Companion App

---

## Overview

The Flutter app is the user-facing control panel for the AI desk bot. It handles device provisioning (BLE), account management (REST), and provides a way to browse conversations, manage memories, and customize the bot's personality.

**Framework:** Flutter
**Key packages:** flutter_blue_plus (BLE scanning/GATT), flutter_ble_peripheral (background BLE advertising for presence), flutter_secure_storage (tokens), dio (HTTP client)

---

## Screens

### Auth screens

| Screen | Description |
|--------|-------------|
| Login | Email + password login, link to register |
| Register | Email + password + name registration |

Auth state is managed with JWT tokens stored in flutter_secure_storage. Access token is attached to all API requests. Refresh token is used automatically when access token expires.

### Device screens

| Screen | Description |
|--------|-------------|
| Device list | Cards for each registered device -- name, status (online/offline), last seen |
| Add device | BLE provisioning flow (see below) |
| Device detail | Hub page with tabs: Settings, Conversations, Memories, Personality |

### Provisioning flow (Add device)

Multi-step wizard:

```
1. Scan for BLE devices
   -> Show list of discovered ESP32 bots
   -> User taps one to connect

2. Wi-Fi setup
   -> User enters SSID and password
   -> App writes to ESP32 over BLE
   -> Wait for Wi-Fi connection confirmation

3. Register device
   -> App calls POST /devices on backend
   -> App writes device token to ESP32 over BLE
   -> Wait for backend connection confirmation

4. Name your bot
   -> User picks a name for the device
   -> App calls PATCH /devices/:id/settings

5. Done
   -> Show success screen
   -> Navigate to device detail
```

### Settings screen

| Setting | Control | API |
|---------|---------|-----|
| Device name | Text field | PATCH /devices/:id/settings |
| Volume | Slider 0-100 | BLE write (0xFFE2-01) + PATCH settings |
| Brightness | Slider 0-100 | BLE write (0xFFE2-02) + PATCH settings |
| Show transcript | Toggle | PATCH /devices/:id/settings |
| Idle timeout | Dropdown (1m, 5m, 10m, 30m) | PATCH /devices/:id/settings |
| Remove device | Destructive button | DELETE /devices/:id |

Settings written over BLE take effect immediately on the device. The API call persists them server-side so they survive device reboots.

### Conversations screen

- Paginated list of conversations, newest first
- Each card shows: date, duration, message count, first line preview
- Tap to expand: full message transcript with role labels (user/assistant)
- Search across all conversations (query parameter on API)

### Memories screen

- List of stored memories grouped by category
- Each memory card shows: fact, category, confidence badge, date learned
- Swipe to delete a memory
- Tap to edit (correct a fact)
- Filter by category (chips: personal, preference, work, hobby, etc.)

### Personality screen

| Field | Control | Description |
|-------|---------|-------------|
| Bot name | Text field | What the bot calls itself |
| Tone | Text field / preset picker | e.g., "friendly", "professional", "sarcastic" |
| Language | Dropdown | Primary response language |
| System prompt | Multi-line text | Advanced: custom system prompt (collapsible) |

### Reminders screen

Configure proactive health and wellness reminders. Each reminder has an enable toggle and interval control.

| Reminder | Controls | Default |
|----------|----------|---------|
| Stand up | Toggle + interval picker (30/45/60/90 min) | On, 60 min |
| Hydration | Toggle + interval picker (30/45/60 min) | On, 45 min |
| Eye break (20-20-20) | Toggle + interval picker (15/20/30 min) | On, 20 min |
| Stretch | Toggle + interval picker (60/90/120 min) | On, 90 min |
| Posture check | Toggle + interval picker (20/30/45 min) | Off, 30 min |
| End of day | Toggle + time picker | On, 18:00 |
| Morning briefing | Toggle | On |
| Idle nudge | Toggle + after picker (1/2/3 hours) | Off, 3 hours |

Additional settings:
- **Work hours** — start/end time (default 08:00-18:00). Reminders only fire during work hours.
- **Reminder cooldown** — minimum gap between any two reminders (default 5 min)

### Pomodoro screen

Accessible from device detail. Shows current pomodoro state or lets user start one.

| State | What's shown |
|-------|-------------|
| No active session | "Start Pomodoro" button, cycle config (focus/break durations) |
| Focus phase | Timer countdown, current cycle, "Stop" button |
| Break phase | Timer countdown, "Skip break" button |

Config:
- Focus duration: 15/20/25/30 min (default 25)
- Short break: 3/5/10 min (default 5)
- Long break: 10/15/20 min (default 15)
- Cycles before long break: 3/4/5 (default 4)

---

### Presence settings screen

Configure BLE presence detection (auto sleep/wake based on phone proximity).

| Setting | Control | Default |
|---------|---------|---------|
| Presence detection | Toggle | On |
| RSSI threshold | Slider (-60 to -90 dBm) with "closer" / "farther" labels | -75 dBm |
| Grace period | Picker (15/30/45/60s) | 45s |
| Silent wake threshold | Picker (2/5/10 min) — absences shorter than this don't trigger spoken greeting | 5 min |

The presence settings screen also shows a live RSSI indicator so the user can calibrate the threshold for their desk setup.

---

## State management

Recommended approach: Riverpod or Bloc for state management.

Key state:
- Auth state (logged in/out, tokens)
- Device list (cached, refreshed on pull)
- Current device (selected device context)
- BLE connection state (scanning, connected, provisioning step)
- BLE presence advertising state (advertising/stopped)

---

## Background BLE presence advertising

After provisioning, the app continuously advertises a known BLE service UUID so the ESP32 can detect the user's phone. This runs in the background even when the app is closed.

```dart
// Using flutter_ble_peripheral
class PresenceAdvertiser {
  static const presenceServiceUuid = '0000FFE4-0000-1000-8000-00805F9B34FB';

  Future<void> start() async {
    await FlutterBlePeripheral().start(
      advertiseData: AdvertiseData(
        serviceUuids: [presenceServiceUuid],
        localName: 'AksaOwner',
      ),
    );
  }

  Future<void> stop() async {
    await FlutterBlePeripheral().stop();
  }
}
```

**Lifecycle:** Started automatically after provisioning. Runs as an Android foreground service (persistent notification: "Aksabot presence active"). On iOS, uses background BLE advertising mode (works but iOS randomizes the advertised address — resolved via BLE bonding during provisioning).

**Battery impact:** ~1-2% per day. BLE advertising is extremely low power.

---

## BLE integration (provisioning)

Using `flutter_blue_plus`:

```dart
// Simplified flow
final devices = await FlutterBluePlus.scan(
  withServices: [Guid('0000FFE0-...')],  // Filter by provisioning service
  timeout: Duration(seconds: 10),
);

final device = devices.first;
await device.connect();

final services = await device.discoverServices();
final wifiService = services.firstWhere((s) => s.uuid == wifiProvisioningUuid);

// Write Wi-Fi credentials
await wifiService.characteristics[0].write(utf8.encode(ssid));
await wifiService.characteristics[1].write(utf8.encode(password));

// Listen for connection status
wifiService.characteristics[2].onValueReceived.listen((value) {
  // 0=disconnected, 1=connecting, 2=connected, 3=failed
});
```

---

## API client

Centralized HTTP client with:
- Base URL configuration (dev/prod)
- JWT token injection via interceptor
- Automatic token refresh on 401
- Error handling and mapping to app-level exceptions

---

## Phase 4 deliverables (weeks 9-11)

1. Auth screens (login, register) with JWT management
2. Device list screen with online/offline status
3. BLE provisioning wizard (full flow)
4. Device settings screen with BLE + REST sync
5. Conversation history browser with search
6. Memory viewer with edit/delete and category filter
7. Personality customization screen
8. Reminders configuration screen (all toggles + intervals)
9. Pomodoro screen (start/stop, config, live status)
10. Device removal with token revocation

---

## Related docs

- [02-auth.md](02-auth.md) — JWT auth flow details
- [06-backend-api.md](06-backend-api.md) — REST API endpoints the app consumes
- [08-ble-provisioning.md](08-ble-provisioning.md) — BLE services and provisioning protocol
