# 08 — BLE Provisioning

---

## Overview

BLE (Bluetooth Low Energy) serves three purposes:

1. **Device provisioning** — getting Wi-Fi credentials and a device token onto the ESP32 without needing an existing network connection
2. **Local device control** — volume, brightness, status monitoring (battery, Wi-Fi signal)
3. **Presence detection** — the ESP32 scans for the phone's BLE advertisement to detect whether the user is at their desk (see [12-features.md](12-features.md))

---

## GATT services

The ESP32 exposes four custom GATT services:

### Wi-Fi provisioning (0xFFE0)

| Characteristic | UUID | Properties | Description |
|---------------|------|------------|-------------|
| SSID | 0xFFE0-01 | Read, Write | Wi-Fi network name (max 32 bytes) |
| Password | 0xFFE0-02 | Write | Wi-Fi password (max 64 bytes, write-only for security) |
| Status | 0xFFE0-03 | Read, Notify | Connection status: 0=disconnected, 1=connecting, 2=connected, 3=failed |

### Device auth (0xFFE1)

| Characteristic | UUID | Properties | Description |
|---------------|------|------------|-------------|
| DeviceToken | 0xFFE1-01 | Write | Backend auth token (write-only, stored in NVS) |
| AuthStatus | 0xFFE1-02 | Read, Notify | Token status: 0=no token, 1=token stored, 2=token validated |

### Device control (0xFFE2)

| Characteristic | UUID | Properties | Description |
|---------------|------|------------|-------------|
| Volume | 0xFFE2-01 | Read, Write | Speaker volume 0-100 |
| Brightness | 0xFFE2-02 | Read, Write | Display brightness 0-100 |

### Device status (0xFFE3)

| Characteristic | UUID | Properties | Description |
|---------------|------|------------|-------------|
| Battery | 0xFFE3-01 | Read, Notify | Battery percentage 0-100 (255 = no battery / USB powered) |
| WiFi RSSI | 0xFFE3-02 | Read | Wi-Fi signal strength in dBm |
| Uptime | 0xFFE3-03 | Read | Device uptime in seconds (uint32) |

### Presence advertising (0xFFE4) — Flutter app side

This is NOT a GATT service on the ESP32. Instead, the **Flutter app advertises** this UUID, and the **ESP32 scans** for it to detect the user's phone.

| Role | What it does |
|------|-------------|
| Flutter app | Advertises service UUID 0xFFE4 in the background (BLE peripheral mode) |
| ESP32 | Periodically scans for 0xFFE4 advertisements, reads RSSI to estimate proximity |

The ESP32 uses the RSSI value to determine presence state (PRESENT / LEAVING / AWAY). See [12-features.md](12-features.md) for the full state machine.

**BLE bonding:** During provisioning, the app and ESP32 establish a BLE bond. This is required for presence detection on iOS, where background BLE advertising uses randomized addresses that can only be resolved by bonded devices.

---

## Provisioning flow

This is the full sequence for setting up a new ESP32 device:

```
Flutter App                          ESP32                          Backend
    |                                  |                               |
    |-- BLE scan ----finds------------>|                               |
    |-- BLE connect ------------------>|                               |
    |                                  |                               |
    |  [User enters Wi-Fi credentials in app]                         |
    |                                  |                               |
    |-- Write SSID (0xFFE0-01) ------->|                               |
    |-- Write Password (0xFFE0-02) --->|                               |
    |                                  |-- Connect to Wi-Fi            |
    |<-- Notify Status=2 (connected) --|                               |
    |                                  |                               |
    |  [App registers device with backend]                            |
    |                                  |                               |
    |-- POST /devices ---------------------------------------->|
    |<-- { device, deviceToken } ----------------------------------|
    |                                  |                               |
    |-- Write DeviceToken (0xFFE1-01)->|                               |
    |                                  |-- Store token in NVS          |
    |<-- Notify AuthStatus=1 ---------|                               |
    |                                  |                               |
    |                                  |-- WebSocket connect --------->|
    |                                  |<-- Connection accepted -------|
    |<-- Notify AuthStatus=2 ---------|                               |
    |                                  |                               |
    |-- BLE disconnect --------------->|                               |
    |                                  |                               |
    [Device is now fully provisioned and connected to backend]
```

### Step-by-step

1. **Discovery:** Flutter app scans for BLE devices advertising the provisioning service UUID (0xFFE0)
2. **Connection:** App connects to discovered ESP32
3. **Bonding:** App initiates BLE bonding with ESP32 (required for presence detection, especially on iOS)
4. **Wi-Fi setup:** User enters SSID and password in app UI -> written to provisioning service
5. **Wi-Fi connect:** ESP32 attempts Wi-Fi connection, notifies status via 0xFFE0-03
6. **Device registration:** App calls `POST /devices` on backend -> receives device token
7. **Token delivery:** App writes device token to 0xFFE1-01
8. **Token storage:** ESP32 stores token in NVS flash (persists across reboots)
9. **Backend connection:** ESP32 connects to backend via WebSocket with token
10. **Validation:** Backend validates token, ESP32 notifies AuthStatus=2
11. **Presence start:** App starts background BLE advertising (0xFFE4). ESP32 starts presence scanning.
12. **Done:** BLE provisioning connection can be closed. Device operates independently over Wi-Fi. Presence detection runs continuously via BLE scanning.

---

## Error handling

| Scenario | ESP32 behavior | App notification |
|----------|---------------|------------------|
| Wrong Wi-Fi password | Status notifies 3 (failed) | App shows error, prompts retry |
| Wi-Fi network not found | Status notifies 3 (failed) after timeout | App shows error |
| Invalid device token | AuthStatus stays at 1, WebSocket rejected | App shows auth error |
| BLE disconnected mid-provisioning | ESP32 retains any already-written values | App can reconnect and resume |

---

## Re-provisioning

If a device needs new Wi-Fi credentials or a new token (e.g., moved to a new network):

1. Device falls back to BLE advertising when it can't connect to Wi-Fi or backend
2. Flutter app discovers it again
3. User can write new Wi-Fi credentials and/or a new device token
4. Old token is revoked on the backend side

---

## Security considerations

- **Password is write-only:** Wi-Fi password cannot be read back over BLE
- **Device token is write-only:** Token cannot be read back over BLE
- **BLE range is limited:** ~10m, requires physical proximity
- **BLE bonding is required:** Established during provisioning. Adds encryption to all BLE communication and is required for iOS presence detection (address resolution)

---

## Related docs

- [02-auth.md](02-auth.md) — Device token auth details
- [05-firmware.md](05-firmware.md) — NVS storage for credentials and tokens
- [09-flutter-app.md](09-flutter-app.md) — App-side provisioning UI
