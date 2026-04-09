# 11 — Future Extensions

Post-V1 features that extend the bot beyond the initial prototype. These are documented now so that V1 design decisions don't accidentally block them.

---

## Extension 1: Expressive servo movement (recommended first)

**Priority:** High — low cost, high personality impact
**Estimated effort:** 1-2 weeks firmware + enclosure redesign
**Prerequisites:** V1 complete (Phase 5 done)

### Concept

The bot stays stationary but moves its head/body using micro servos to express emotion. A head tilt when confused or a nod when listening makes the bot feel alive — this is the single highest-impact upgrade for perceived personality.

### Hardware

| Component | Purpose | GPIO | Est. cost |
|-----------|---------|------|-----------|
| SG90 micro servo x1 | Head tilt (pitch: up/down) | 1 PWM pin | Rp 10,000 |
| SG90 micro servo x1 | Head turn (yaw: left/right) | 1 PWM pin | Rp 10,000 |
| SG90 micro servo x1 (optional) | Body lean/wiggle | 1 PWM pin | Rp 10,000 |
| Pan-tilt bracket | Mounting platform for head servos | -- | Rp 25,000 |
| Redesigned enclosure | Separate head + body, servo mounts, cable routing | -- | Rp 100,000 |
| **Total** | | **2-3 GPIO pins** | **Rp 155,000** |

SG90 servos draw ~150mA under load, ~10mA idle. Acceptable for USB-C power, but budget for it on battery.

### Motion profiles

Each bot state maps to a motion profile — a sequence of servo positions over time.

| State | Head pitch | Head yaw | Body lean | Description |
|-------|-----------|----------|-----------|-------------|
| Idle | 0° (center) | 0° (center) | 0° | Resting, occasional subtle shift every 10-15s |
| Listening | +5° (slight up) | toward user | 0° | Attentive, slight lean-in |
| Thinking | 0° | slow oscillate ±10° | 0° | Looking around, considering |
| Speaking | subtle nod ±3° | 0° | 0° | Rhythmic nod loosely synced to speech cadence |
| Happy | quick +10° up, settle | 0° | slight wiggle | Perky, energetic |
| Confused | +10° tilt | -15° (one side) | 0° | Classic head tilt, hold for 1-2s |
| Sleeping | -15° (drooped) | 0° | 0° | Slow droop on idle timeout, slow breathing motion |
| Surprised | quick -5° (pull back) | 0° | 0° | Startled pullback, then recover |
| Greeting | +10° up, settle to 0° | 0° | 0° | Perk up when user starts interaction |
| Error/offline | -5° | -10° | 0° | Slight droop + tilt, sad posture |

### Firmware additions

```
New module: servo_controller
  - servo_init(pin, min_pulse, max_pulse)
  - servo_set_angle(servo_id, angle, speed_ms)
  - servo_play_profile(profile_id)      -- plays a timed sequence of positions
  - servo_set_idle_behavior(enabled)     -- subtle random movements when idle
```

**FreeRTOS task:**

| Task | Priority | Core | Description |
|------|----------|------|-------------|
| servo_control | Low | 1 | Servo position interpolation and profile playback |

Low priority — servos should never preempt audio. Runs on core 1 alongside display.

### Motion sync with bot state

The existing face animation state machine already manages state transitions. Servo motion hooks into the same state changes:

```
on_state_change(new_state):
  update_face_animation(new_state)    // existing
  update_servo_profile(new_state)     // new
```

For speaking state, the servo nod rhythm can be driven by audio amplitude (same data the mouth animation uses).

### Enclosure redesign

The V1 enclosure is a single static housing. For servos, the design changes to:

```
        ┌──────────┐
        │  Display  │  <- Head (mounted on pan-tilt)
        │  (face)   │
        └────┬─────┘
             │  <- Neck (pan-tilt bracket, 2 servos)
        ┌────┴─────┐
        │   Body    │  <- Base (stationary, optional lean servo)
        │  Speaker  │
        │  USB-C    │
        └──────────┘
```

Head and body are separate 3D-printed parts connected by the servo bracket. Cables route through the neck.

### Settings (Flutter app)

| Setting | Control | Default |
|---------|---------|---------|
| Motion enabled | Toggle | On |
| Motion intensity | Slider (subtle / normal / expressive) | Normal |
| Idle fidget | Toggle (subtle random movements when idle) | On |

These are stored in `devices.settings_json` and synced to ESP32 via BLE or WebSocket.

---

## Extension 2: Desk mobility (ambitious — separate phase)

**Priority:** Low — high complexity, unclear value over expressive servos
**Estimated effort:** 4-6 weeks firmware + new chassis + navigation logic
**Prerequisites:** V1 complete, Extension 1 done (expressive movement first)

### Concept

The bot drives around the desk on wheels using differential drive, with sensors to avoid falling off edges and bumping into objects. This turns the bot from a stationary companion into a mobile desk robot.

**Honest assessment:** This is fun but changes the project's nature from AI companion to robotics project. Only pursue this if the stationary bot feels limiting in practice.

### Hardware

| Component | Purpose | Interface | Est. cost |
|-----------|---------|-----------|-----------|
| N20 micro gear motor x2 | Differential drive (left/right wheels) | PWM via motor driver | Rp 30,000 |
| DRV8833 dual motor driver | ESP32 GPIO can't drive motors directly (2A per channel) | 4 GPIO pins (2 per motor: PWM + DIR) | Rp 15,000 |
| TCRT5000 IR cliff sensor x3 | Detect desk edge (front-left, front-center, front-right) | 3 analog GPIO pins | Rp 15,000 |
| VL53L0X ToF distance sensor | Obstacle detection (50mm-1200mm range, I2C, better than ultrasonic) | I2C (shared bus) | Rp 20,000 |
| MPU6050 IMU | Orientation, tilt detection, fall detection | I2C (shared bus) | Rp 15,000 |
| Wheel encoder x2 (optional) | Accurate distance and position tracking | 2 interrupt GPIO pins | Rp 30,000 |
| LiPo battery 3000mAh | Motors need more power than stationary bot | -- | Rp 40,000 |
| New chassis (wheels, mounts) | Completely different form factor from V1 | -- | Rp 150,000 |
| **Total** | | **~9-11 additional GPIO pins** | **Rp 315,000** |

### GPIO budget concern

The ESP32-S3 has plenty of GPIO pins total (~45), but many are already allocated:

```
Currently used:
  I2S mic:     3 pins (BCLK, WS, DATA)
  I2S speaker: 3 pins (BCLK, WS, DATA) — may share clock with mic
  SPI display: 4 pins (CLK, MOSI, DC, CS) + 1 backlight
  SPI touch:   1 pin (CS, shares SPI bus with display)
  Servos:      2-3 pins (from Extension 1)

Mobility adds:
  Motor driver: 4 pins
  Cliff sensors: 3 analog pins
  I2C bus:      2 pins (SDA, SCL) — shared by VL53L0X + MPU6050
  Encoders:     2 pins (optional)

Total: ~25 pins used of ~45 available — feasible but requires careful pin planning
```

Pin conflicts to watch: I2C bus shared with touch controller (if capacitive touch uses I2C), ADC channels needed for cliff sensors may conflict with other analog uses.

### Navigation system

Desk navigation is hard. The bot operates in an unmapped, dynamic environment with lethal edges.

#### Safety layers (priority order)

```
1. CLIFF DETECTION (highest priority — interrupt-driven)
   - 3x IR sensors check desk edge continuously
   - Any sensor triggered -> immediate motor stop + reverse
   - Runs as ISR, not a task — cannot be preempted
   - This is the "don't die" layer

2. OBSTACLE AVOIDANCE
   - VL53L0X ToF sensor scans forward
   - Object detected < 100mm -> stop, turn, find clear path
   - Runs at 10Hz in navigation task

3. TILT DETECTION
   - MPU6050 monitors pitch/roll
   - Tilt > 15° -> emergency stop (bot is on an edge or uneven surface)
   - Runs at 50Hz in navigation task

4. BEHAVIOR LAYER (lowest priority)
   - Decides where to go: wander, approach user, return to base
   - Only runs when safety layers report all-clear
```

#### Movement behaviors

| Behavior | Trigger | Description |
|----------|---------|-------------|
| Idle park | Default | Bot stays still, no motor activity |
| Approach user | User starts talking | Bot turns toward sound source (if mic array is added) or toward a learned "user position" |
| Wander | After long idle | Slow random exploration within safe bounds |
| Return to base | Low battery / sleep | Navigate back to charging position (requires a docking marker or learned position) |
| Retreat | Cliff or obstacle | Reverse, turn, find clear path |
| Dance | Happy emotion | Small spin or wiggle in place (fun, not functional) |

#### Position awareness (optional)

Without encoders, the bot has no idea where it is on the desk. With encoders:
- Dead reckoning: track distance traveled per wheel
- Build a rough mental map of desk boundaries (cliff sensor triggers)
- Remember a "home" position to return to
- Accuracy degrades over time (wheel slip, drift) — good enough for a desk, not for precision

### Firmware additions

```
New modules:
  motor_controller
    - motor_init(driver_pins)
    - motor_set_speed(left, right)       -- -100 to +100 per wheel
    - motor_stop()                       -- immediate stop
    - motor_emergency_stop()             -- ISR-safe, highest priority

  cliff_detector
    - cliff_init(sensor_pins[3])
    - cliff_check() -> { left, center, right }   -- true = edge detected
    - cliff_on_detect(callback)                   -- ISR registration

  navigation
    - nav_init(motor, cliff, obstacle, imu)
    - nav_set_behavior(behavior_id)
    - nav_get_state() -> { position, heading, behavior, safety_status }

  obstacle_detector
    - obstacle_init(vl53l0x_i2c_addr)
    - obstacle_get_distance() -> mm
    - obstacle_is_clear(threshold_mm) -> bool

  imu
    - imu_init(mpu6050_i2c_addr)
    - imu_get_orientation() -> { pitch, roll, yaw }
    - imu_is_tilted(threshold_degrees) -> bool
```

**FreeRTOS tasks:**

| Task | Priority | Core | Description |
|------|----------|------|-------------|
| cliff_isr | Critical | -- | Interrupt handler, not a task — immediate motor stop |
| navigation | Medium | 1 | Behavior execution, obstacle avoidance, path planning |
| sensor_poll | Medium | 1 | Read ToF, IMU at regular intervals |

### Power impact

| Component | Current draw | Notes |
|-----------|-------------|-------|
| 2x N20 motors (moving) | 100-300mA each | Only when driving |
| 2x N20 motors (stall) | up to 800mA each | Avoid stall conditions |
| DRV8833 driver | ~10mA quiescent | Negligible |
| 3x TCRT5000 | ~20mA each | Always on for safety |
| VL53L0X | ~20mA active | Can be duty-cycled when stationary |
| MPU6050 | ~5mA | Always on for tilt detection |
| **Total added** | **~300-700mA** | **Significant — battery life drops from hours to ~1 hour** |

USB-C power (500mA-3A) is fine. Battery operation becomes limited — consider a charging dock as part of the mobility design.

### Chassis design

Completely different form factor from the stationary V1 enclosure:

```
        ┌──────────┐
        │  Display  │  <- Head (on servo pan-tilt, from Extension 1)
        │  (face)   │
        └────┬─────┘
             │       <- Neck
        ┌────┴─────┐
        │   Body    │  <- Main housing: ESP32, speaker, battery, motor driver
        │ ┌──┐ ┌──┐│
        │ │L │ │R ││  <- Left/right wheels (underneath)
        │ └──┘ └──┘│
        │  [cliff] │  <- 3x cliff sensors on front underside
        │  [ToF]   │  <- Forward-facing distance sensor
        └──────────┘
           ○    ○     <- Caster ball or skid (rear support)
```

### Settings (Flutter app)

| Setting | Control | Default |
|---------|---------|---------|
| Mobility enabled | Toggle | Off |
| Wander behavior | Toggle | Off |
| Movement speed | Slider (slow / normal) | Slow |
| Desk boundary learning | Button (start calibration) | -- |

---

## Extension 3: Backend integrations (low effort)

**Priority:** Medium — useful utility features, no hardware changes
**Estimated effort:** 1-3 days per integration on backend
**Prerequisites:** V1 Phase 3+ (memory service working)

These extend what the bot can talk about by adding API integrations on the backend. No firmware changes needed — the bot just gets smarter responses because the LLM has more context.

### Integration architecture

Integrations are injected as **tools** available to the LLM. The prompt includes tool descriptions, and the LLM can choose to call them when relevant.

```typescript
// src/ai/interfaces/tool-provider.interface.ts
export interface ToolDefinition {
  name: string;
  description: string;
  parameters: Record<string, unknown>;    // JSON Schema
}

export interface ToolResult {
  content: string;
}

export interface IToolProvider {
  getDefinitions(): ToolDefinition[];
  execute(name: string, params: Record<string, unknown>): Promise<ToolResult>;
}
```

This follows the same ports and adapters pattern — each integration implements `IToolProvider`.

### Planned integrations

| Integration | Trigger phrases | Backend addition |
|-------------|----------------|------------------|
| Weather | "what's the weather", "will it rain" | OpenWeatherMap API |
| Calendar | "do I have meetings", "what's my schedule" | Google Calendar API (OAuth) |
| News | "what's happening today", "any news" | NewsAPI or RSS feeds |
| Timer/alarm | "set a timer for 5 minutes", "remind me in 1 hour" | Backend scheduler + WebSocket push to ESP32 |
| Unit conversion | "convert 50 USD to IDR" | Exchange rate API or let LLM handle it |
| Home automation | "turn off the lights" | Home Assistant API (if user has HA instance) |

### Timer/alarm (special case)

This one requires a small firmware addition — the backend needs to push a notification to the ESP32 at a specific time.

```
New WebSocket event:
  alert:trigger | Server -> ESP | { type: 'timer' | 'reminder', message: string }
```

ESP32 plays an alert sound and shows the message on screen. Simple, no new hardware.

---

## Extension 4: Camera and vision (long-term)

**Priority:** Low — requires different board or camera module
**Estimated effort:** 4-6 weeks
**Prerequisites:** V1 complete

### Concept

Add a camera so the bot can see its environment. This enables:
- Recognize when the user sits down / walks away
- Read text from physical objects (show me this receipt)
- Visual context in conversations ("what's on my desk")
- Gesture recognition (wave to wake)

### Hardware options

The Hosyond ESP32-S3 2.8" board does NOT have a camera connector. Options:

1. **Add OV2640 camera module** via a separate ESP32-CAM connected over UART/I2C — janky but works
2. **Switch to ESP32-S3-EYE** or similar board with built-in camera — cleaner but requires firmware port
3. **Use a separate USB camera** connected to the backend (if bot is near a computer) — easiest but breaks the self-contained design

Camera processing would happen on the backend (send JPEG frames over WebSocket, process with Gemini vision), not on the ESP32.

**Not specced further here — revisit when V1 is stable and there's a clear vision use case.**

---

## Extension priority order

| # | Extension | Effort | Impact | Recommendation |
|---|-----------|--------|--------|----------------|
| 1 | Expressive servos | 1-2 weeks | Very high | Do this first — biggest personality boost for least effort |
| 2 | Backend integrations | 1-2 weeks | Medium | Do alongside or after servos — adds utility |
| 3 | Desk mobility | 4-6 weeks | Medium | Only if stationary feels limiting after daily use |
| 4 | Camera/vision | 4-6 weeks | High (if done well) | Long-term, may require hardware change |

---

## Related docs

- [05-firmware.md](05-firmware.md) — Current firmware module structure and GPIO usage
- [06-backend-api.md](06-backend-api.md) — Ports and adapters pattern (used for tool integrations)
- [10-risks-and-scope.md](10-risks-and-scope.md) — V1 scope boundaries
