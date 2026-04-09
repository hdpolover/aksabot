# Aksabot Flutter App — UI/UX Proposal

> Companion app for the Aksabot AI desk companion. Controls device setup, personality,
> reminders, and conversation history. Built with Flutter, Material 3, BLoC pattern.

---

## 1. Design Principles

| Principle | What it means |
|-----------|--------------|
| **Companion, not dashboard** | The app supports the physical bot — it isn't the main interaction surface. Keep screens shallow and task-oriented. |
| **Glanceable** | Most screens should communicate status in under 2 seconds. Use color, iconography, and layout hierarchy. |
| **Progressive disclosure** | Show essential controls upfront; hide advanced options behind expandable sections or "Advanced" labels. |
| **Consistent Material 3** | Use the existing indigo seed color (0xFF6366F1), M3 color roles, and the Inter typeface throughout. |

---

## 2. Navigation Architecture

### Bottom Navigation Bar (post-auth)

Replace the current flat route list with a `NavigationBar` (M3) with 3 destinations:

| Tab | Icon | Label | Root Screen |
|-----|------|-------|-------------|
| Home | `Icons.home_outlined` | Home | Device dashboard (or device list if multiple) |
| Activity | `Icons.history` | Activity | Conversations + Memories (segmented) |
| Settings | `Icons.settings_outlined` | Settings | App settings + account |

**Why 3 tabs, not 5:** Most users will have one device. Splitting reminders, pomodoro,
personality, etc. into separate tabs creates too many top-level destinations for a
companion app. Group them under the device screen instead.

### Full Route Map

```
/login
/register

/ (shell with bottom nav)
  /home
    /home/add-device                → BLE provisioning wizard (5-step)
    /home/devices/:id               → Device dashboard
      /home/devices/:id/personality
      /home/devices/:id/reminders
      /home/devices/:id/pomodoro
      /home/devices/:id/focus
      /home/devices/:id/presence
      /home/devices/:id/settings
      /home/devices/:id/stats
      /home/devices/:id/firmware     (planned)
      /home/devices/:id/display      (planned — Phase 2)
      /home/devices/:id/voice        (planned — Phase 5)
      /home/devices/:id/motion       (planned — future)
      /home/devices/:id/mobility     (planned — future)
      /home/devices/:id/diagnostics  (planned)
      /home/devices/:id/integrations (planned — future)
  /activity
    /activity/conversations/:deviceId
    /activity/conversations/:deviceId/:conversationId
    /activity/memories/:deviceId
  /settings
    /settings/account
```

---

## 3. Screen-by-Screen Spec

### 3.1 Auth — Login & Register

**Current state:** Done. Minor tweaks proposed.

| Change | Rationale |
|--------|-----------|
| Add app logo/icon above the "Welcome back" heading | Brand recognition, visual anchor |
| Add "Forgot password?" link below the password field | Standard UX expectation (backend not implemented yet — can be a no-op or toast) |
| Smooth transition between login ↔ register | Use `Hero` on the logo and shared field animations |

---

### 3.2 Home Tab — Device Dashboard

**When the user has 0 devices:**

Full-screen empty state:
- Illustrated bot icon (or Lottie animation of the bot face)
- "No devices yet"
- "Pair your Aksabot to get started"
- Primary button: **"Add Device"** → opens BLE provisioning wizard

**When the user has 1 device (common case):**

Single-device dashboard. No device list — go straight to the device view:

```
┌─────────────────────────────────┐
│  [Bot avatar/icon]   "Aksa"     │
│  ● Online · Uptime 4h 23m      │
│                                 │
│  ┌──────────┐  ┌──────────┐    │
│  │ 🎯 Focus │  │ 🍅 Pomo  │    │
│  │   Mode   │  │  25:00   │    │
│  │   OFF    │  │  Idle    │    │
│  └──────────┘  └──────────┘    │
│                                 │
│  Quick Actions                  │
│  ┌─────────────────────────┐   │
│  │ 🗣  Personality          → │ │
│  │ ⏰  Reminders            → │ │
│  │ 🍅  Pomodoro             → │ │
│  │ 🎯  Focus Mode           → │ │
│  │ 📡  Presence             → │ │
│  │ 🖥  Display & Face       → │ │
│  │ 🔊  Voice & Audio        → │ │
│  │ 📊  Stats                → │ │
│  │ ⚙️  Device Settings      → │ │
│  └─────────────────────────┘   │
│                                 │
│  Recent Conversations           │
│  "Hey, remind me about..."  3m │
│  "What's the weather..."   1h  │
└─────────────────────────────────┘
```

Key components:
- **Status header**: Bot name, online indicator (green dot), uptime
- **Status cards row**: 2 cards side-by-side showing Focus Mode and Pomodoro state at a glance
- **Quick actions list**: ListTiles navigating to sub-screens. Grouped in a Card.
- **Recent conversations**: Last 2-3 conversations as compact preview tiles
- **FAB**: Hidden (no need — the device is already paired)

**When the user has 2+ devices:**

Device list (current DevicesPage) with cards. Tapping a card opens the single-device dashboard above.

- **FAB**: "Add Device" button to pair another

---

### 3.3 BLE Provisioning Wizard (New)

5-step wizard using a `Stepper` or custom `PageView` with progress indicator.

**Step 1 — Scan**
```
┌─────────────────────────────────┐
│  ← Add Device          Step 1/5│
│                                 │
│  [Scanning animation - radar]   │
│                                 │
│  Looking for Aksabot devices... │
│                                 │
│  ┌─ Aksabot-A3F2 ──── -62 dBm ┐│
│  │  ESP32-S3 · Not configured  ││
│  └─────────────────────────────┘│
│  ┌─ Aksabot-B1C4 ──── -78 dBm ┐│
│  │  ESP32-S3 · Not configured  ││
│  └─────────────────────────────┘│
│                                 │
│  Can't find your device?        │
│  Make sure it's powered on and  │
│  in pairing mode.               │
└─────────────────────────────────┘
```

- `ListView` of discovered BLE devices filtered by Aksabot service UUID
- Signal strength indicator (icon or bar)
- Tap to select → BLE connect + bond → advance to Step 2
- Troubleshooting hint at bottom

**Step 2 — Wi-Fi Setup**
```
┌─────────────────────────────────┐
│  ← Add Device          Step 2/5│
│                                 │
│  Connect to Wi-Fi               │
│                                 │
│  Network name                   │
│  ┌─────────────────────────────┐│
│  │ [SSID field, prefilled if  ]││
│  │ [phone's current network   ]││
│  └─────────────────────────────┘│
│  Password                       │
│  ┌─────────────────────────────┐│
│  │ [password field + eye icon ]││
│  └─────────────────────────────┘│
│                                 │
│  [Connecting... progress bar]   │
│                                 │
│  [ Next →                     ] │
└─────────────────────────────────┘
```

- Pre-fill SSID from the phone's current Wi-Fi (requires `network_info_plus`)
- Write credentials to ESP32 via BLE (GATT 0xFFE0)
- Show connection status: Disconnected → Connecting → Connected / Failed
- On success → advance to Step 3
- On failure → show error, allow retry

**Step 3 — Register Device**
```
┌─────────────────────────────────┐
│  ← Add Device          Step 3/5│
│                                 │
│  Registering with server...     │
│                                 │
│  [Progress animation]           │
│                                 │
│  ✓ Wi-Fi connected              │
│  ✓ Device registered            │
│  ● Writing auth token...        │
│  ○ Verifying connection         │
└─────────────────────────────────┘
```

- Automatic step — no user input needed
- POST /devices → get device token → write to ESP32 (GATT 0xFFE1)
- Checklist with animated check marks as each sub-step completes
- On failure → show retry button with error detail

**Step 4 — Name Your Bot**
```
┌─────────────────────────────────┐
│  ← Add Device          Step 4/5│
│                                 │
│  [Bot face illustration]        │
│                                 │
│  What should I call myself?     │
│                                 │
│  ┌─────────────────────────────┐│
│  │ Aksa                        ││
│  └─────────────────────────────┘│
│                                 │
│  You can change this later in   │
│  personality settings.          │
│                                 │
│  [ Next →                     ] │
└─────────────────────────────────┘
```

- Single text field, pre-filled with "Aksa"
- Friendly illustration of the bot
- PATCH /devices/:id/settings with the name

**Step 5 — Done**
```
┌─────────────────────────────────┐
│                         Step 5/5│
│                                 │
│  [Success animation - confetti] │
│                                 │
│  You're all set!                │
│                                 │
│  Aksa is online and ready to    │
│  chat. Just tap or speak.       │
│                                 │
│  [ Go to Dashboard →          ] │
└─────────────────────────────────┘
```

- Success animation (Lottie confetti or check mark)
- Start BLE presence advertising in background
- Navigate to device dashboard

---

### 3.4 Device Settings

Accessible from the Quick Actions list on the device dashboard.

```
┌─────────────────────────────────┐
│  ← Device Settings              │
│                                 │
│  General                        │
│  ┌─────────────────────────────┐│
│  │ Device name     [Aksa     ]││
│  │ Volume          [====|----]││
│  │ Brightness      [======|--]││
│  │ Show transcript    [toggle]││
│  │ Idle timeout    [30 min  ▾]││
│  └─────────────────────────────┘│
│                                 │
│  Device Info                    │
│  ┌─────────────────────────────┐│
│  │ Status        ● Online      ││
│  │ Wi-Fi signal  ▂▄▆█ Good     ││
│  │ Uptime        4h 23m        ││
│  │ Firmware      v1.0.0        ││
│  └─────────────────────────────┘│
│                                 │
│  [ Remove Device ]  (destructive│
│                      outlined)  │
└─────────────────────────────────┘
```

- Volume/Brightness sliders write to ESP32 via BLE (GATT 0xFFE2) for immediate effect, then sync to backend
- Device info card reads from BLE status service (GATT 0xFFE3) when connected, falls back to backend data
- "Remove Device" is an `OutlinedButton` with error color, triggers confirmation dialog

---

### 3.5 Personality Screen

```
┌─────────────────────────────────┐
│  ← Personality                  │
│                                 │
│  [Bot avatar with name below]   │
│                                 │
│  Bot name                       │
│  ┌─────────────────────────────┐│
│  │ Aksa                        ││
│  └─────────────────────────────┘│
│                                 │
│  Tone                           │
│  ┌─ Friendly ──────────────────┐│
│  │  ○ Professional             ││
│  │  ● Friendly                 ││
│  │  ○ Playful                  ││
│  │  ○ Sarcastic               ││
│  │  ○ Custom...               ││
│  └─────────────────────────────┘│
│                                 │
│  Language                       │
│  ┌─────────────────────────────┐│
│  │ English               ▾    ││
│  └─────────────────────────────┘│
│                                 │
│  ▸ Advanced                     │
│  ┌─────────────────────────────┐│
│  │ System prompt (optional)    ││
│  │ ┌─────────────────────────┐ ││
│  │ │ [multi-line textarea]   │ ││
│  │ └─────────────────────────┘ ││
│  └─────────────────────────────┘│
│                                 │
│  [ Save ]                       │
└─────────────────────────────────┘
```

- Tone uses radio buttons with curated presets instead of a free text field (friendlier UX)
- "Custom..." preset reveals a text field for free-form tone description
- System prompt hidden under an "Advanced" expandable — most users won't touch it
- Save button only enabled when changes detected (dirty state)

---

### 3.6 Reminders Screen

```
┌─────────────────────────────────┐
│  ← Reminders                    │
│                                 │
│  Work Hours                     │
│  ┌─────────────────────────────┐│
│  │ Start   [08:00]  End [18:00]││
│  │ Reminders only fire during  ││
│  │ work hours.                 ││
│  └─────────────────────────────┘│
│                                 │
│  Health                         │
│  ┌─────────────────────────────┐│
│  │ 🧍 Stand up        60 min ▾││
│  │                     [=====]││
│  ├─────────────────────────────┤│
│  │ 💧 Hydration        45 min ▾││
│  │                     [=====]││
│  ├─────────────────────────────┤│
│  │ 👁 Eye break        20 min ▾││
│  │                     [=====]││
│  ├─────────────────────────────┤│
│  │ 🤸 Stretch          90 min ▾││
│  │                     [=====]││
│  ├─────────────────────────────┤│
│  │ 🪑 Posture check    30 min ▾││
│  │                     [  off]││
│  └─────────────────────────────┘│
│                                 │
│  Daily                          │
│  ┌─────────────────────────────┐│
│  │ ☀ Morning briefing  [=====]││
│  │ 🌙 End of day    18:00 [==]││
│  │ 💤 Idle nudge     3h  [ off]││
│  └─────────────────────────────┘│
└─────────────────────────────────┘
```

- Grouped into "Health" and "Daily" sections with card containers
- Each reminder: icon + label + interval dropdown + toggle switch
- Work hours at the top as a separate card — sets the boundary for all reminders
- Time pickers for morning briefing and end-of-day (use `showTimePicker`)
- Changes save immediately on toggle/dropdown change (optimistic update pattern already in place)

---

### 3.7 Pomodoro Screen

```
┌─────────────────────────────────┐
│  ← Pomodoro                     │
│                                 │
│        ┌───────────────┐        │
│        │               │        │
│        │    25:00      │        │
│        │   FOCUS 3/4   │        │
│        │               │        │
│        └───────────────┘        │
│   (circular progress ring)      │
│                                 │
│  ┌──────────┐  ┌──────────┐    │
│  │  ⏭ Skip  │  │  ⏹ Stop  │    │
│  └──────────┘  └──────────┘    │
│                                 │
│  ▸ Settings                     │
│  ┌─────────────────────────────┐│
│  │ Focus       [25 min  ▾]    ││
│  │ Short break [ 5 min  ▾]    ││
│  │ Long break  [15 min  ▾]    ││
│  │ Cycles      [ 4      ▾]    ││
│  └─────────────────────────────┘│
│                                 │
│  Today: 6 focus sessions        │
│  Total focus time: 2h 30m       │
└─────────────────────────────────┘
```

- Large circular progress indicator as the hero element (use `CustomPainter` or a package like `percent_indicator`)
- Phase label inside the ring: "FOCUS 3/4" or "BREAK"
- Phase-aware colors: primary for focus, tertiary for short break, secondary for long break
- Two action buttons when active: Skip (advance to next phase) and Stop
- One button when idle: Start
- Settings in an expandable section below
- Daily stats at the bottom (focus count + total time) — read from backend

---

### 3.8 Presence Settings Screen (New)

```
┌─────────────────────────────────┐
│  ← Presence Detection           │
│                                 │
│  ┌─────────────────────────────┐│
│  │ Enable presence   [=======]││
│  │                             ││
│  │ When your phone is nearby,  ││
│  │ Aksa wakes up and greets    ││
│  │ you. When you leave, Aksa   ││
│  │ goes to sleep.              ││
│  └─────────────────────────────┘│
│                                 │
│  Sensitivity                    │
│  ┌─────────────────────────────┐│
│  │ Farther ────●──── Closer    ││
│  │                             ││
│  │ Current RSSI: -68 dBm  ● ● ││
│  │ (live indicator dots)       ││
│  │                             ││
│  │ Grace period    [45 sec  ▾] ││
│  │ (delay before sleep)        ││
│  └─────────────────────────────┘│
│                                 │
│  Behavior                       │
│  ┌─────────────────────────────┐│
│  │ Silent wake if away         ││
│  │ less than      [ 5 min  ▾] ││
│  │                             ││
│  │ Skips the greeting if you   ││
│  │ just stepped away briefly.  ││
│  └─────────────────────────────┘│
└─────────────────────────────────┘
```

- Toggle at top to enable/disable the entire feature
- RSSI slider with human labels ("Farther" / "Closer") instead of raw dBm
- Live RSSI indicator: animated dots that pulse based on current signal strength — helps user calibrate the slider while sitting at their desk
- Grace period dropdown: how long after losing signal before bot sleeps
- Silent wake threshold: avoids the greeting if you were away briefly
- Helpful descriptions below each control (bodySmall, onSurfaceVariant color)

---

### 3.9 Activity Tab — Conversations & Memories

Top of the screen: `SegmentedButton` (M3) to switch between Conversations and Memories views.

**Conversations view:**
```
┌─────────────────────────────────┐
│  Activity                       │
│  [Conversations] [Memories]     │
│                                 │
│  🔍 Search conversations...     │
│                                 │
│  Today                          │
│  ┌─────────────────────────────┐│
│  │ "Hey, remind me about the  ││
│  │  meeting tomorrow"          ││
│  │  3:42 PM · 2 min · 4 msgs  ││
│  └─────────────────────────────┘│
│  ┌─────────────────────────────┐│
│  │ "What's the best way to    ││
│  │  handle async errors in..."  ││
│  │  11:15 AM · 8 min · 12 msgs ││
│  └─────────────────────────────┘│
│                                 │
│  Yesterday                      │
│  ┌─────────────────────────────┐│
│  │ ...                         ││
│  └─────────────────────────────┘│
└─────────────────────────────────┘
```

- Grouped by day with sticky headers
- Search bar at top (filters via API query param)
- Card shows first message preview, timestamp, duration, message count
- Tap card → conversation detail with full transcript (existing `_MessageBubble` pattern)
- If multiple devices: show device name chip on each conversation

**Memories view:**
```
┌─────────────────────────────────┐
│  Activity                       │
│  [Conversations] [Memories]     │
│                                 │
│  [All] [Personal] [Work] [Pref]│
│                                 │
│  Personal                       │
│  ┌─────────────────────────────┐│
│  │ Likes dark roast coffee     ││
│  │ Confidence: 92%   Apr 8    ← │
│  └─────────────────────────────┘│
│  ┌─────────────────────────────┐│
│  │ Works at a standing desk    ││
│  │ Confidence: 78%   Apr 5    ← │
│  └─────────────────────────────┘│
│                                 │
│  Work                           │
│  ...                            │
└─────────────────────────────────┘
```

- Same as current memories page but within the tabbed layout
- Filter chips, grouped by category, swipe-to-delete, tap-to-edit

---

### 3.10 Settings Tab

```
┌─────────────────────────────────┐
│  Settings                       │
│                                 │
│  Account                        │
│  ┌─────────────────────────────┐│
│  │ 👤 Hendra                   ││
│  │    hendra@example.com       ││
│  └─────────────────────────────┘│
│                                 │
│  App                            │
│  ┌─────────────────────────────┐│
│  │ Theme          [System  ▾] ││
│  │ Notifications     [=====]  ││
│  └─────────────────────────────┘│
│                                 │
│  About                          │
│  ┌─────────────────────────────┐│
│  │ Version         1.0.0       ││
│  │ Licenses        →           ││
│  └─────────────────────────────┘│
│                                 │
│  [ Sign Out ]                   │
│  (outlined, error color)        │
└─────────────────────────────────┘
```

- Account card shows name + email from auth state
- Theme selector: System / Light / Dark
- Notifications toggle (for push notifications — future feature)
- Sign out button at the bottom, error-colored outline

---

### 3.11 OTA Firmware Updates (Planned)

```
┌─────────────────────────────────┐
│  ← Firmware Update               │
│                                 │
│  Current version                │
│  ┌─────────────────────────────┐│
│  │ Installed     v1.0.0        ││
│  │ Available     v1.1.0        ││
│  │ Size          1.2 MB        ││
│  └─────────────────────────────┘│
│                                 │
│  What's new in v1.1.0           │
│  ┌─────────────────────────────┐│
│  │ • Improved voice activity   ││
│  │   detection (VAD)           ││
│  │ • Better Wi-Fi reconnect    ││
│  │ • Bug fixes                 ││
│  └─────────────────────────────┘│
│                                 │
│  ┌─────────────────────────────┐│
│  │  Downloading...  43%        ││
│  │  ████████░░░░░░░░░░░░       ││
│  │                             ││
│  │  Do not power off your      ││
│  │  device during update.      ││
│  └─────────────────────────────┘│
│                                 │
│  [ Update Now ]                 │
│  (disabled during download)     │
└─────────────────────────────────┘
```

- Accessed from Device Settings → "Firmware" row, or via push notification when update is available
- Shows current vs. available version, changelog, download size
- Progress bar during download + flash stages
- Warning text: "Do not power off your device during update"
- Three states: up-to-date (green check), update available (primary button), updating (progress bar + disabled button)
- ESP32 uses A/B OTA partition — rollback if boot fails, shown as "Update failed — rolled back to v1.0.0" in the UI

---

### 3.12 Focus Mode Screen (Planned)

```
┌─────────────────────────────────┐
│  ← Focus Mode                    │
│                                 │
│  ┌─────────────────────────────┐│
│  │        🎯 FOCUSING          ││
│  │                             ││
│  │     Deep work session       ││
│  │     Started 45 min ago      ││
│  │                             ││
│  │     Reminders: paused       ││
│  │     Nudges: silenced        ││
│  └─────────────────────────────┘│
│                                 │
│  [ End Focus Mode ]             │
│                                 │
│  ─── or when inactive ───       │
│                                 │
│  ┌─────────────────────────────┐│
│  │ Enable focus mode   [=====]││
│  └─────────────────────────────┘│
│                                 │
│  Behavior during focus          │
│  ┌─────────────────────────────┐│
│  │ Pause reminders     [=====]││
│  │ Silence nudges      [=====]││
│  │ Allow pomodoro      [=====]││
│  │ Dim display         [=====]││
│  │ Auto-end after   [  off  ▾]││
│  │   (off / 1h / 2h / 4h)     ││
│  └─────────────────────────────┘│
│                                 │
│  When focus ends, Aksa gives    │
│  you a summary of what you      │
│  missed.                        │
└─────────────────────────────────┘
```

- Two visual states: active (hero card with status) and inactive (toggle + config)
- Configurable what gets paused: reminders, idle nudges, display brightness
- Option to allow pomodoro to continue during focus (since it's structured work)
- Auto-end timer: prevents forgetting to turn it off
- On exit: bot delivers a summary of missed reminders/events via WebSocket

---

### 3.13 Device Statistics Screen (Planned)

```
┌─────────────────────────────────┐
│  ← Device Stats                  │
│                                 │
│  Today                          │
│  ┌──────────┐  ┌──────────┐    │
│  │    12    │  │  2h 15m  │    │
│  │  convos  │  │  talk    │    │
│  └──────────┘  └──────────┘    │
│  ┌──────────┐  ┌──────────┐    │
│  │     6    │  │    47    │    │
│  │  pomodoro│  │ memories │    │
│  └──────────┘  └──────────┘    │
│                                 │
│  This week                      │
│  ┌─────────────────────────────┐│
│  │ M  T  W  T  F  S  S        ││
│  │ █  █  █  ▄  ░  ░  ░        ││
│  │ Conversations per day       ││
│  └─────────────────────────────┘│
│                                 │
│  Cache                          │
│  ┌─────────────────────────────┐│
│  │ TTS cache    23 entries     ││
│  │ Response pool  8 / 15       ││
│  │ [  Refill Pool  ]          ││
│  └─────────────────────────────┘│
│                                 │
│  System                         │
│  ┌─────────────────────────────┐│
│  │ Uptime       4h 23m         ││
│  │ Free PSRAM   5.2 MB         ││
│  │ Wi-Fi RSSI   -58 dBm        ││
│  │ Flash used   62%             ││
│  └─────────────────────────────┘│
└─────────────────────────────────┘
```

- Accessible from device dashboard (new "Stats" row in Quick Actions)
- Top: today's usage metrics in a 2x2 grid of stat cards
- Weekly bar chart (simple, using `fl_chart` or custom painter)
- Cache section: TTS cache size, response pool fill level, manual "Refill Pool" button (calls `POST /scheduler/:deviceId/pool/refill`)
- System section: hardware stats from BLE status service (GATT 0xFFE3) or backend

---

### 3.14 Integrations Screen (Planned — Future)

```
┌─────────────────────────────────┐
│  ← Integrations                  │
│                                 │
│  Connected                      │
│  ┌─────────────────────────────┐│
│  │ 🌤  Weather                  │
│  │    OpenWeatherMap · Active  ││
│  │                    [=====] ││
│  └─────────────────────────────┘│
│                                 │
│  Available                      │
│  ┌─────────────────────────────┐│
│  │ 📅  Google Calendar          │
│  │    Morning briefing, events ││
│  │               [ Connect → ] ││
│  ├─────────────────────────────┤│
│  │ 📰  News                    │
│  │    Headlines in briefing    ││
│  │               [ Connect → ] ││
│  ├─────────────────────────────┤│
│  │ 🏠  Home Assistant          │
│  │    Smart home voice control ││
│  │               [ Connect → ] ││
│  ├─────────────────────────────┤│
│  │ 🎵  Spotify                 │
│  │    Music control via voice  ││
│  │               [ Connect → ] ││
│  └─────────────────────────────┘│
│                                 │
│  Integrations let Aksa access   │
│  external services to give you  │
│  richer responses and control.  │
└─────────────────────────────────┘
```

- Two sections: "Connected" (active) and "Available" (not yet configured)
- Each integration card: icon, name, brief description, toggle or connect button
- "Connect" opens OAuth flow or API key input depending on the service
- Connected integrations show a toggle to enable/disable without disconnecting
- Future integrations listed in docs: Weather, Calendar, News, Home Assistant, Spotify, Todoist

---

### 3.15 Servo & Motion Settings (Planned — Future)

```
┌─────────────────────────────────┐
│  ← Motion & Expression          │
│                                 │
│  ┌─────────────────────────────┐│
│  │ Enable motion       [=====]││
│  │                             ││
│  │ Aksa can move its head and  ││
│  │ body to express emotions    ││
│  │ while talking.              ││
│  └─────────────────────────────┘│
│                                 │
│  Expression intensity           │
│  ┌─────────────────────────────┐│
│  │ Subtle ───●──── Expressive  ││
│  └─────────────────────────────┘│
│                                 │
│  Behaviors                      │
│  ┌─────────────────────────────┐│
│  │ Nod while listening [=====]││
│  │ Look at user        [=====]││
│  │ React to speech     [=====]││
│  │ Idle fidget         [=====]││
│  └─────────────────────────────┘│
│                                 │
│  Calibration                    │
│  ┌─────────────────────────────┐│
│  │ [ Calibrate Center ]        ││
│  │ Sets the resting position   ││
│  │ for the servos.             ││
│  └─────────────────────────────┘│
└─────────────────────────────────┘
```

- Master toggle to enable/disable all servo movement
- Intensity slider: maps to servo angle range (subtle = small movements, expressive = full range)
- Individual behavior toggles: which contexts trigger movement
- Calibration button: puts servos in center position so user can adjust mounting
- Depends on hardware extension (2x SG90 servos for pan/tilt)

---

### 3.16 Desk Mobility Settings (Planned — Future)

```
┌─────────────────────────────────┐
│  ← Desk Mobility                 │
│                                 │
│  ┌─────────────────────────────┐│
│  │ Enable mobility     [=====]││
│  │                             ││
│  │ Aksa can move around your   ││
│  │ desk using its wheels.      ││
│  └─────────────────────────────┘│
│                                 │
│  Movement                       │
│  ┌─────────────────────────────┐│
│  │ Speed                       ││
│  │ Slow ─────●───── Normal     ││
│  │                             ││
│  │ Wander when idle    [=====]││
│  │ Come closer when              │
│  │ talking            [=====]││
│  └─────────────────────────────┘│
│                                 │
│  Safety                         │
│  ┌─────────────────────────────┐│
│  │ [ Learn Desk Boundaries ]   ││
│  │                             ││
│  │ Drive Aksa to each edge of  ││
│  │ your desk to teach it the   ││
│  │ safe area.                  ││
│  │                             ││
│  │ Status: Calibrated ✓        ││
│  │ Last: Apr 8, 2026           ││
│  └─────────────────────────────┘│
│                                 │
│  [ Emergency Stop ]             │
│  (always visible, error color)  │
└─────────────────────────────────┘
```

- Master toggle for mobility
- Speed slider (safety-first — "Normal" is still moderate)
- Behavioral toggles: idle wandering, approach-on-speak
- Boundary calibration: guided flow where user manually drives the bot to desk edges
- Calibration status: shows whether boundaries are set and when
- Persistent emergency stop button (error-colored `FilledButton`)
- Depends on hardware extension (2x N20 motors + TB6612 driver + cliff sensors)

---

### 3.17 Display & Face Settings (Planned)

```
┌─────────────────────────────────┐
│  ← Display & Face                │
│                                 │
│  Preview                        │
│  ┌─────────────────────────────┐│
│  │                             ││
│  │     (  o   o  )             ││
│  │        ───                  ││
│  │   [live face preview]       ││
│  │                             ││
│  └─────────────────────────────┘│
│                                 │
│  Face Style                     │
│  ┌─────────────────────────────┐│
│  │ ● Default                   ││
│  │ ○ Minimal                   ││
│  │ ○ Kawaii                    ││
│  │ ○ Pixel                    ││
│  └─────────────────────────────┘│
│                                 │
│  Colors                         │
│  ┌─────────────────────────────┐│
│  │ Eye color    [●] Indigo     ││
│  │ Background   [●] Black      ││
│  └─────────────────────────────┘│
│                                 │
│  Idle Display Mode              │
│  ┌─────────────────────────────┐│
│  │ ○ Face (default)            ││
│  │ ○ Clock                     ││
│  │ ○ Pomodoro timer            ││
│  │ ○ Weather                   ││
│  │ ○ Screen off                ││
│  └─────────────────────────────┘│
│                                 │
│  ┌─────────────────────────────┐│
│  │ Brightness      [======|--]││
│  │ Auto-dim at night   [=====]││
│  └─────────────────────────────┘│
└─────────────────────────────────┘
```

- Live preview of the face at the top (mirrored from the TFT display if BLE-connected, otherwise static illustration)
- Face style presets: different eye/mouth drawing styles
- Color pickers for eye color and background
- Idle display mode: what shows on the TFT when not in conversation
- Brightness slider (synced with Device Settings brightness)
- Auto-dim toggle for nighttime
- Depends on Phase 2 hardware (TFT display + face animation engine)

---

### 3.18 Voice & Audio Settings (Planned)

```
┌─────────────────────────────────┐
│  ← Voice & Audio                 │
│                                 │
│  Voice                          │
│  ┌─────────────────────────────┐│
│  │ Voice preset                ││
│  │ ┌─────────────────────────┐ ││
│  │ │ Ziggy (energetic boy) ▾│ ││
│  │ └─────────────────────────┘ ││
│  │                             ││
│  │ Speed                       ││
│  │ Slower ────●──── Faster     ││
│  │                             ││
│  │ Stability                   ││
│  │ Variable ──●──── Stable     ││
│  │                             ││
│  │ [ Preview Voice ]           ││
│  └─────────────────────────────┘│
│                                 │
│  Audio                          │
│  ┌─────────────────────────────┐│
│  │ Wake sound          [=====]││
│  │ Sleep sound         [=====]││
│  │ Reminder chime      [=====]││
│  └─────────────────────────────┘│
│                                 │
│  Advanced                       │
│  ┌─────────────────────────────┐│
│  │ VAD sensitivity             ││
│  │ Less ─────●───── More       ││
│  │                             ││
│  │ VAD determines when you've  ││
│  │ stopped talking. Higher =   ││
│  │ more responsive, but may    ││
│  │ cut you off sooner.         ││
│  └─────────────────────────────┘│
└─────────────────────────────────┘
```

- Voice preset dropdown: list of available ElevenLabs voices (fetched from backend or hardcoded initial set)
- Speed and stability sliders map to ElevenLabs TTS parameters (currently hardcoded in backend)
- "Preview Voice" button: plays a sample TTS clip through the phone speaker
- Audio toggles: enable/disable sound effects for wake, sleep, reminder chime
- VAD sensitivity slider: controls voice activity detection threshold on ESP32
- Depends on Phase 5 (VAD) for the advanced section

---

### 3.19 Debug & Diagnostics Screen (Planned)

```
┌─────────────────────────────────┐
│  ← Diagnostics                   │
│                                 │
│  Connection Test                │
│  ┌─────────────────────────────┐│
│  │ Backend API    ✓  42ms      ││
│  │ WebSocket      ✓  connected ││
│  │ BLE            ✓  -62 dBm  ││
│  │ Wi-Fi (ESP32)  ✓  -55 dBm  ││
│  │                             ││
│  │ [ Run Test ]                ││
│  └─────────────────────────────┘│
│                                 │
│  Audio Pipeline Test            │
│  ┌─────────────────────────────┐│
│  │ [ Test Mic → STT → LLM     ││
│  │   → TTS → Speaker ]        ││
│  │                             ││
│  │ Last test: passed (1.8s)    ││
│  └─────────────────────────────┘│
│                                 │
│  Device Logs                    │
│  ┌─────────────────────────────┐│
│  │ [14:23:01] WS connected     ││
│  │ [14:23:02] Audio session     ││
│  │ [14:23:05] STT: "hello"     ││
│  │ [14:23:06] LLM streaming    ││
│  │ [14:23:07] TTS: 2 chunks    ││
│  │ ...                         ││
│  │                             ││
│  │ [ Export Logs ]             ││
│  └─────────────────────────────┘│
│                                 │
│  [ Factory Reset Device ]       │
│  (destructive, confirmation)    │
└─────────────────────────────────┘
```

- Connection test: pings backend API, checks WebSocket, reads BLE + Wi-Fi RSSI
- Audio pipeline test: triggers a full round-trip test (audio → STT → LLM → TTS → audio) and reports latency
- Device logs: scrollable log viewer reading from ESP32's MicroSD via BLE or from backend WebSocket debug events
- Export logs: shares log file via system share sheet
- Factory reset: clears device config, revokes token, removes from backend — with double confirmation dialog
- Accessible from Device Settings → "Diagnostics" or from the Settings tab

---

## 4. Connectivity Patterns

### 4.1 BLE Connection States

The app has two BLE roles:
1. **Active connection** — during provisioning and settings changes (volume, brightness)
2. **Passive advertising** — for presence detection (always-on background)

Connection state widget (shown on device dashboard header):

| State | Visual | Description |
|-------|--------|-------------|
| BLE connected | Blue Bluetooth icon | Active BLE session to device |
| BLE disconnected | Grey Bluetooth icon | No active BLE link (normal when not configuring) |
| Advertising | Small broadcast icon | Presence advertising active |

### 4.2 Network Status

Show a persistent banner at the top of the app when:
- **No internet**: Red banner — "No internet connection. Some features unavailable."
- **Backend unreachable**: Orange banner — "Can't reach server. Retrying..."
- **Device offline**: Subtle chip on device dashboard — "Device offline" (already have the green dot, add an offline state)

Use `connectivity_plus` for network monitoring. Banner dismisses automatically when connection is restored.

### 4.3 Offline Behavior

| Feature | Online | Offline |
|---------|--------|---------|
| View conversations/memories | Cached locally | Read-only from cache |
| Change reminders/pomodoro | Syncs to backend | Queue changes, sync on reconnect |
| BLE provisioning | Required (registers device) | Blocked with clear message |
| Presence advertising | Independent | Works (BLE only) |
| Device settings (volume/brightness) | BLE + API sync | BLE only, API sync later |

---

## 5. Visual Design Direction

### Color Roles

| Role | Usage |
|------|-------|
| Primary (Indigo) | Main actions, active states, focus phase, online indicator |
| Secondary (derived) | Long break phase, secondary actions |
| Tertiary (derived) | Short break phase, accent |
| Error (derived) | Destructive actions, offline banners, delete |
| Surface variants | Card backgrounds, input fills, secondary surfaces |

### Iconography

Use Material Symbols (rounded, weight 400) throughout. Key icons:

| Context | Icon |
|---------|------|
| Device | `smart_toy` |
| Online | Green filled circle (custom) |
| Offline | Grey outlined circle (custom) |
| Conversations | `chat_bubble_outline` |
| Memories | `psychology` |
| Reminders | `notifications_active` |
| Pomodoro | `timer` |
| Focus Mode | `center_focus_strong` |
| Presence | `bluetooth_searching` |
| Settings | `settings` |
| Personality | `face` |
| Display & Face | `monitor` |
| Voice & Audio | `graphic_eq` |
| Statistics | `bar_chart` |
| Firmware/OTA | `system_update` |
| Diagnostics | `troubleshoot` |
| Integrations | `extension` |
| Motion/Servo | `animation` |
| Mobility | `open_with` |
| Emergency Stop | `emergency` |

### Motion

- **Page transitions**: Shared axis (horizontal) between sibling routes, container transform for list → detail
- **State changes**: Fade through for tab switches
- **Loading**: Skeleton shimmer on list pages (not just `CircularProgressIndicator`)
- **Provisioning**: Step transitions with slide animation

### Typography Scale (Inter)

| Element | Style |
|---------|-------|
| Screen titles | `headlineMedium` |
| Section headers | `titleMedium` |
| Card titles | `titleSmall` |
| Body text | `bodyMedium` |
| Captions/hints | `bodySmall` + `onSurfaceVariant` |
| Large display (pomodoro timer) | `displayLarge` |

---

## 6. Implementation Priority

Listed in dependency order — each phase builds on the previous. Screens marked
**(planned UI)** will be built as fully navigable UI with placeholder/mock data
where the backend or hardware support isn't ready yet.

### Phase A — Navigation Restructure + Dashboard
- Add `NavigationBar` shell route with 3 tabs (Home, Activity, Settings)
- Refactor existing pages into the new route structure
- Build device dashboard as the home screen (single-device view)
- Move conversations + memories under Activity tab with `SegmentedButton`
- Build Settings tab (account, theme, sign out)
- Focus Mode screen (planned UI — backend already supports it)
- Device Statistics screen (planned UI — wire to existing pool/stats endpoints)

### Phase B — Connectivity Layer
- Add `flutter_blue_plus` for BLE scanning and GATT operations
- Add `connectivity_plus` for network monitoring
- Build connection state banner widget (no internet / backend unreachable / device offline)
- Wire BLE into device settings (volume, brightness via GATT 0xFFE2)
- Read device status from BLE (GATT 0xFFE3) for device info card

### Phase C — BLE Provisioning Wizard
- 5-step `PageView` with progress indicator
- BLE scan → Wi-Fi setup → device registration → naming → done
- Integrate with existing backend device creation API

### Phase D — Presence Detection
- Build presence settings screen
- Add `flutter_ble_peripheral` for background BLE advertising
- Live RSSI indicator widget
- Wire into backend presence events

### Phase E — Display, Voice & Audio (Planned UI)
- Display & Face settings screen (planned UI — face style, colors, idle mode)
- Voice & Audio settings screen (planned UI — voice preset, speed, stability, VAD)
- "Preview Voice" TTS playback through phone speaker
- These screens are fully navigable but depend on Phase 2 (TFT) and Phase 5 (VAD) hardware

### Phase F — OTA & Diagnostics (Planned UI)
- OTA firmware update screen (planned UI — version check, changelog, progress bar)
- Diagnostics screen (planned UI — connection test, audio pipeline test, device logs, factory reset)
- Export logs via system share sheet

### Phase G — Integrations (Planned UI — Future)
- Integrations management screen (planned UI — connected/available list)
- OAuth / API key input flows per integration
- Weather, Calendar, News, Home Assistant, Spotify, Todoist placeholders

### Phase H — Motion & Mobility (Planned UI — Future)
- Servo & Motion settings screen (planned UI — intensity slider, behavior toggles, calibration)
- Desk Mobility settings screen (planned UI — speed, wander, boundary calibration, emergency stop)
- Depends on hardware extensions (servos, motors, cliff sensors)

### Phase I — Polish
- Skeleton loading shimmer on all list screens
- Offline caching with Hive or drift
- Page transitions (shared axis, container transform)
- Push notification support
- Accessibility audit (semantic labels, contrast, font scaling)

---

## 7. Screen Inventory Summary

| # | Screen | Status | Phase | Hardware Dep |
|---|--------|--------|-------|-------------|
| 3.1 | Login / Register | Done | — | — |
| 3.2 | Device Dashboard | New | A | — |
| 3.3 | BLE Provisioning Wizard | New | C | ESP32 BLE |
| 3.4 | Device Settings | Rework | A | BLE for volume/brightness |
| 3.5 | Personality | Rework | A | — |
| 3.6 | Reminders | Existing | A | — |
| 3.7 | Pomodoro | Rework | A | — |
| 3.8 | Presence Settings | New | D | ESP32 BLE |
| 3.9 | Activity (Conversations + Memories) | Rework | A | — |
| 3.10 | Settings Tab | New | A | — |
| 3.11 | OTA Firmware Update | Planned UI | F | ESP32 OTA |
| 3.12 | Focus Mode | Planned UI | A | — |
| 3.13 | Device Statistics | Planned UI | A | — |
| 3.14 | Integrations | Planned UI | G | External APIs |
| 3.15 | Servo & Motion | Planned UI | H | Servos |
| 3.16 | Desk Mobility | Planned UI | H | Motors + cliff sensors |
| 3.17 | Display & Face | Planned UI | E | TFT display |
| 3.18 | Voice & Audio | Planned UI | E | VAD on ESP32 |
| 3.19 | Debug & Diagnostics | Planned UI | F | — |

**Total: 19 screens** (4 existing rework, 4 new, 2 done, 9 planned UI)

---

## 8. Open Questions

1. **Single-device shortcut**: Should the home tab always show the dashboard (assuming 1 device), or should there be an explicit device list even for 1 device? The proposal assumes dashboard-first.

2. **BLE always-on**: Continuous BLE advertising for presence may impact battery. Should there be a "power saver" mode that disables advertising and relies on manual wake?

3. **Theme customization**: Should users be able to pick a custom accent color, or stick with the indigo brand color? Proposing system indigo for now.

4. **Conversation search**: Full-text search requires a backend endpoint with LIKE/tsvector query. Not currently implemented. Should this be backend search or client-side filter on loaded data?

5. **Offline-first vs. online-only**: How aggressively should we cache? The proposal suggests light caching (conversations, memories) but not a full offline-first architecture. Worth the complexity?

6. **Planned UI depth**: For screens where the backend/hardware isn't ready (OTA, integrations, motion, mobility) — should the planned UI show realistic mock data, or just empty states with "Coming soon" labels? Mock data is more useful for design validation but takes more effort.

7. **Face style customization**: How many face presets should we ship initially? The wireframe shows 4 (Default, Minimal, Kawaii, Pixel). Is this enough, or should we allow custom face uploads?

8. **Integration priority**: Which integrations matter most? Weather and Calendar seem highest value for the morning briefing. Spotify and Home Assistant are cool but complex. Recommend starting with Weather + Calendar.
