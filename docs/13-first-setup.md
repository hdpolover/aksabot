# First-Time Setup Guide

Everything you need to go from unboxing to a working Aksabot.

---

## Prerequisites

| Tool | Install |
|------|---------|
| Docker & Docker Compose | [docker.com](https://www.docker.com/products/docker-desktop/) |
| Node.js 20+ | `brew install node` |
| PlatformIO CLI | `pip3 install platformio` |
| Flutter (FVM) | `dart pub global activate fvm && fvm install 3.41.6` |
| USB-C cable | For first firmware flash |

---

## Step 1 — Start the backend

```bash
cd backend

# Start PostgreSQL + Redis
docker-compose up -d

# Install dependencies
npm install

# Copy env and fill in your API keys
cp .env.example .env
# Edit .env — set GEMINI_API_KEY, GOOGLE_APPLICATION_CREDENTIALS, ELEVENLABS_API_KEY

# Run database migration
npm run migration:run

# Start the backend
npm run start:dev
```

Verify: `curl http://localhost:4280/` should respond.

---

## Step 2 — Flash the ESP32 firmware

This is the only step that requires a USB cable. After this, updates are OTA.

### 2a. Connect hardware

1. Plug the ESP32-S3 N16R8 into your Mac via USB-C
2. Verify it shows up:
   ```bash
   ls /dev/cu.usb*
   # Should show something like /dev/cu.usbmodem14101
   ```

### 2b. Set environment variables

The firmware needs to know where your backend is. For first-time setup, we hardcode these via environment variables (BLE provisioning replaces this later):

```bash
# Your home Wi-Fi
export AKSABOT_WIFI_SSID="YourWifiName"
export AKSABOT_WIFI_PASS="YourWifiPassword"

# Backend WebSocket URL (use your Mac's local IP, not localhost)
# Find your IP: ipconfig getifaddr en0
export AKSABOT_WS_URL="ws://192.168.x.x:4280/ws"

# Device token — create one first (see step 2c)
export AKSABOT_DEVICE_TOKEN="your-device-token-here"
```

### 2c. Create a device on the backend

Before flashing, you need a device token. Run the ESP simulator to create one:

```bash
cd backend
npm run esp:sim
# Copy the Device Token from the output, then Ctrl+C
```

Paste that token as `AKSABOT_DEVICE_TOKEN` above.

### 2d. Flash

```bash
cd firmware
pio run --target upload
```

PlatformIO will:
1. Download the ESP32-S3 toolchain (first time only, ~500MB)
2. Compile the firmware
3. Flash it to the board

### 2e. Monitor serial output

```bash
pio device monitor
```

You should see:
```
=== Aksabot Firmware ===

[Log] File logging enabled → /logs/debug.log
[NVS] Initialized — free entries: 498
[SD] Mounted — Type: SDHC, Size: 7564MB, Used: 0MB
[Cache] Loaded manifest: 0 entries, 0KB
[Resilience] 0/7 clips loaded
[Presence] Init — threshold=-75dBm, grace=45s, window=5
[Display HW] Init (stub — no TFT connected)
[Face] Initialized
[Touch] Initialized (serial simulation active)
[VAD] Init — energy=0.020, silence_frames=75 (1.5s)
[Power] Init — dim=30s, sleep=300s
[WiFi] Using compile-time credentials for 'YourWifiName'
[WiFi] Connected — IP: 192.168.x.x
[WS] Connecting to ws://192.168.x.x:4280/ws...
[WS] Connected

[Main] Ready! Controls: s=start, e=end, i=interrupt, q=quit, w=wake
```

If you see this, the ESP32 is online. Check the Flutter app — the device should show a green dot.

### 2f. Test the audio pipeline

In the serial monitor:
1. Press `s` → starts recording (face switches to LISTENING)
2. Speak into the mic
3. Recording auto-stops after 1.5s of silence (VAD) or press `e` to stop manually
4. Wait for response — you should hear audio from the speaker
5. Press `i` during playback to interrupt

---

## Step 3 — Run the Flutter app

```bash
cd app

# Install dependencies
fvm flutter pub get

# Create .env (already exists with default)
# API_BASE_URL=http://127.0.0.1:4280

# Run on iOS simulator
fvm flutter run

# Or specify a device
fvm flutter devices          # list available
fvm flutter run -d <device>  # run on specific device
```

### First login

1. Register a new account in the app (or use `test@aksabot.local` / `TestPass123!` if you ran the ESP simulator)
2. Your ESP32 device should appear on the dashboard
3. If not, go to **Add Device → Wi-Fi** and connect via the SoftAP flow

---

## Step 4 — Pair via the app (alternative to hardcoded creds)

If you prefer not to hardcode Wi-Fi credentials in the firmware, use BLE provisioning instead:

### Option A: Bluetooth (recommended)
1. Flash the firmware **without** the Wi-Fi env vars (it will boot into pairing mode)
2. In the app: **Add Device → Bluetooth**
3. Scan → select your Aksabot → enter Wi-Fi credentials → done

### Option B: Wi-Fi (SoftAP)
1. Flash the firmware without Wi-Fi env vars
2. ESP32 creates hotspot `Aksabot-XXXX`
3. Connect your phone to that hotspot
4. In the app: **Add Device → Wi-Fi**
5. Enter your home Wi-Fi credentials → done

Both methods store the credentials in NVS flash — they persist across reboots.

---

## Step 5 — Verify everything works

| Check | How |
|-------|-----|
| Backend running | `curl http://localhost:4280/` |
| Database ready | `docker ps` shows postgres + redis healthy |
| ESP32 online | Green dot on app dashboard |
| Audio pipeline | Speak to the ESP32, check serial monitor for STT output |
| Full round-trip | Speak → hear Aksa respond (requires GEMINI_API_KEY + ELEVENLABS_API_KEY) |

---

## Testing without hardware

You can test everything except the physical audio/display without the ESP32:

```bash
# Terminal 1: Backend
cd backend && docker-compose up -d && npm run start:dev

# Terminal 2: ESP simulator (keeps a virtual device online)
cd backend && npm run esp:sim

# Terminal 3: Flutter app
cd app && fvm flutter run

# Terminal 4: Full audio test (sends real audio through the pipeline)
cd backend && npm run ws:sim
```

The ESP simulator creates a device that shows as online in the app. The WebSocket simulator (`ws:sim`) sends actual Opus-encoded audio through the full STT → LLM → TTS pipeline.

---

## Troubleshooting

### ESP32 not detected via USB
- Try a different USB-C cable (some are charge-only)
- On macOS, check System Information → USB for the device
- Try holding BOOT button while plugging in, then release

### Flash fails with "Failed to connect"
- Hold the **BOOT** button on the ESP32
- Click upload in PlatformIO
- Release BOOT when upload starts

### ESP32 can't connect to Wi-Fi
- Check SSID/password (case-sensitive)
- ESP32 only supports **2.4GHz** Wi-Fi, not 5GHz
- Make sure your router isn't blocking new devices

### ESP32 connects to Wi-Fi but not WebSocket
- Check `AKSABOT_WS_URL` — must be your Mac's local IP, not `localhost` or `127.0.0.1`
- Make sure the backend is running (`npm run start:dev`)
- Check that port 4280 isn't blocked by a firewall

### App says "Device offline" but ESP32 is connected
- Pull-to-refresh on the dashboard
- The device is "online" if `lastSeenAt` is within the last 5 minutes
- Check backend logs for WebSocket connection events

---

## Hardware reference

| Component | Spec |
|-----------|------|
| Board | ESP32-S3 N16R8 (Hosyond) |
| Flash | 16MB |
| PSRAM | 8MB (OPI) |
| USB | USB-C (built-in JTAG) |
| Audio | I2S INMP441 mic + MAX98357A speaker |
| Display | 2.8" IPS TFT 320x240 with capacitive touch (ST7789 or ILI9341) |
| Storage | MicroSD via SPI |

### GPIO pinout

| Pin | Function |
|-----|----------|
| 5 | I2S Mic BCLK |
| 6 | I2S Mic WS |
| 7 | I2S Mic DATA |
| 15 | I2S Speaker BCLK |
| 16 | I2S Speaker WS |
| 17 | I2S Speaker DATA |
| 10 | MicroSD CS |
| 11 | SPI MOSI |
| 12 | SPI CLK |
| 13 | SPI MISO |

---

## Hardware integration checklist

When the ESP32 arrives, work through these in order:

### Priority 1: Basic connectivity
- [ ] Flash firmware (`pio run --target upload`)
- [ ] Verify serial output matches expected boot sequence above
- [ ] Confirm Wi-Fi connects and WebSocket goes online
- [ ] Test serial touch simulation (s/e/i/q/w)
- [ ] Test audio: speak → check STT transcript in serial
- [ ] Test VAD: stop speaking → verify auto-stop after 1.5s silence
- [ ] Test TTS playback through speaker
- [ ] Check SD card mount and directory creation

### Priority 2: Display
- [ ] Identify TFT driver IC (check markings: ST7789 or ILI9341)
- [ ] Add TFT library to `platformio.ini` (TFT_eSPI or LovyanGFX)
- [ ] Implement `display_hw::init()` — SPI setup, rotation, clear
- [ ] Implement `display_hw::renderFace()` — draw eyes + mouth from `FaceState`
- [ ] Verify face expression transitions (idle → listening → thinking → speaking)
- [ ] Implement remaining render functions (clock, pomodoro, reminder, status)
- [ ] Implement `display_hw::setBacklight()` — PWM brightness control
- [ ] Test power management dimming and sleep

### Priority 3: Touch
- [ ] Identify capacitive touch IC
- [ ] Add touch library to `platformio.ini`
- [ ] Implement SPI reads in `touch::feedRaw()`
- [ ] Test tap-to-talk hold detection
- [ ] Test tap-to-interrupt during playback
- [ ] Test wake from sleep on touch
- [ ] Test long press (3s) for session end

### Priority 4: BLE provisioning
- [ ] Implement BLE GATT server (4 services: FFE0-FFE3)
- [ ] Test with Flutter app: scan → connect → Wi-Fi creds → token write
- [ ] Verify NVS storage (Wi-Fi reconnects after reboot with stored creds)
- [ ] Test SoftAP fallback provisioning flow

### Priority 5: BLE presence
- [ ] Implement BLE scanner for 0xFFE4 UUID
- [ ] Wire to `presence_detector::feedRssi()`
- [ ] Test with Flutter app presence advertising
- [ ] Verify auto-sleep when phone leaves range
- [ ] Verify auto-wake + greeting when phone returns
- [ ] Calibrate RSSI threshold for your desk setup

### Priority 6: Polish
- [ ] Tune VAD sensitivity for your mic (calibrate noise floor)
- [ ] Test OTA update flow (download + verify, flash when `apply()` is implemented)
- [ ] Migrate Serial.printf calls to LOG_I/W/E macros
- [ ] Test resilience audio (add .opus files to `/audio/resilience/` on SD card)
- [ ] Test recording buffer (disconnect Wi-Fi mid-recording, reconnect, verify resend)
- [ ] Load test: run for 24 hours, check memory leaks, SD space, cache behavior
