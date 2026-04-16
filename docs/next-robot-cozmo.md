# Next Project — Cozmo-Like Robot

> Written after completing Aksabot (desk companion, ESP32-S3 based).
> This doc captures the research, platform decisions, and build roadmap
> for the next hardware project: a mobile, expressive robot inspired by Anki Cozmo.

---

## Why Cozmo

Cozmo is the right reference point because it nails the three things that make a
robot feel alive:

1. **Personality choreography** — face + movement + sound all synchronized
2. **Physical presence** — it moves through and reacts to the world
3. **Character** — hesitant, curious, frustrated, celebratory behaviors

The key insight: you've already built #1 and #3 with Aksabot (AI pipeline,
emotion tagging, face animations, memory, scheduler). The Cozmo build is
primarily about adding the physical body. The soul is already done.

---

## What Cozmo actually consists of

| Component | Description |
|-----------|-------------|
| Treads | Differential drive — personality comes from how it moves |
| Head tilt | 1 servo — up=curious, down=sad/thinking |
| Lift arm | 2 servos — fork mechanism for picking up cubes |
| Camera | Face/object detection, obstacle avoidance |
| Expressive face | Animated LCD screen |
| Personality AI | Emotion-driven reactions to environment |
| Self-charging | Drives to dock when battery is low |

---

## Platform decision: Raspberry Pi + Pico

### Why not just extend the current ESP32-S3

The Aksabot ES3C28P board has **zero free pins for a camera** (DVP needs 10+
GPIO). All pins are consumed by display, audio, SD, touch, BLE, USB. It cannot
be extended for a mobile robot. Aksabot is also a dev module — the display is
soldered to the board and not being torn down for reuse.

### Why Raspberry Pi

| | ESP32 | Raspberry Pi |
|---|---|---|
| Camera | Impossible on current board | Native CSI — plug and play |
| Computer vision | Very limited | OpenCV, TensorFlow Lite, MediaPipe |
| Python ecosystem | No | Full |
| ROS2 | No | First-class |
| Boot time | Instant | 15-30 seconds |
| Power draw idle | ~0.5W | ~3-5W |
| Real-time motor control | Native | **Not real-time** |

The critical limitation of RPi for robotics: **Linux is not real-time**. The
scheduler introduces jitter that makes tight motor PID loops unreliable. This
is why every serious robot uses both a Pi and a microcontroller.

### Recommended model: Raspberry Pi 4 Model B, 8GB

Not Zero 2W (512MB RAM is tight for camera + WebSocket + CV simultaneously).
Not Pi 5 (better single-core performance, but higher idle power draw ~5-7W vs
Pi 4's ~3-5W, needs active cooling, and the extra compute isn't needed since
heavy AI work happens on the VPS).

The 8GB variant was picked over 4GB specifically to avoid running out of
memory when adding extras later — CCTV streaming, motion detection, local
model fallback, dashboards. $10-15 extra for peace of mind.

- Quad-core 1.8GHz Cortex-A72
- 8GB LPDDR4-3200 RAM
- 85mm x 56mm x 17mm — fits in a robot body
- ~$75 USD (expect Indonesian retail markup)

### Microcontroller for motor control: Raspberry Pi Pico 2 (~$5)

The Pico 2 (RP2350) is better than ESP32 for pure motor control:
- Dual programmable I/O (PIO) state machines for precise PWM timing
- No OS overhead
- Cheap — $5
- Not the Pico 2 W — the wireless radio is wasted silicon here since the
  Pico talks to the Pi over UART, not WiFi

---

## Architecture

```
NestJS backend (VPS) — existing Aksabot backend, reused as-is
        ↕ WebSocket
Raspberry Pi 4 8GB (robot brain)
  - Camera (CSI) — face/object recognition, ArUco markers for docking
  - Python — high-level logic, CV, coordination, audio playback
  - I2S DAC + speaker for TTS output
  - Single WebSocket client to backend
        ↕ UART
Raspberry Pi Pico 2 (real-time controller)
  - Motor PID loops (differential drive treads)
  - Servo control (head tilt, lift arm x2) via PCA9685
  - ST7789 SPI LCD — face animations (ported from Aksabot C++)
  - Encoder feedback (odometry)
  - IMU — MPU-6050 (orientation, tilt, tap/shake detection)
  - IR receiver — dock homing beacon
  - Battery voltage ADC monitoring
```

**Role split:**

- **Pi decides *what* to do** — receives backend events, runs CV, makes
  navigation decisions, manages state, routes everything.
- **Pico decides *how* to do it** — executes commands with tight timing,
  coordinates face + servo + motor sequences, reports sensor data up.

Pi sends high-level commands over UART like `animate:curious`,
`drive:forward:0.3`, `dock:approach`. Pico handles the execution.

The existing Aksabot ES3C28P board stays untouched — it remains the desk
companion. The robot is a separate physical build with its own display and
audio, but reuses the entire NestJS backend.

---

## Hardware bill of materials

### Core compute

| Part | Purpose | Est. Cost |
|------|---------|-----------|
| Raspberry Pi 4 Model B 8GB | Robot brain | $75 |
| Pi Camera Module 3 (or OV5647) | Vision | $10-25 |
| Raspberry Pi Pico 2 | Real-time controller | $5 |
| 32GB microSD (Class 10/A2) | Pi OS + storage | $5-8 |

### Drive system

| Part | Purpose | Est. Cost |
|------|---------|-----------|
| Mini tank chassis kit (2 DC motors with encoders) | Treads + frame | $10-15 |
| TB6612FNG motor driver | Dual motor driver, less heat than L298N | $2-5 |

Note: Get motors with encoders already attached (search for "N20 encoder
motor" or "TT motor with encoder"). Adding encoders to bare motors is
miserable.

### Servos & motion

| Part | Purpose | Est. Cost |
|------|---------|-----------|
| MG90S servo x3 | Head tilt + arm shoulder + arm wrist | $6 |
| PCA9685 PWM board | 16-channel I2C servo driver, frees Pico pins | $3 |

Consider upgrading the head tilt servo to a digital servo (DS3218 or similar)
later — MG90S has noticeable gear slop that kills fine "hesitant tilt"
micro-movements. Fine for prototyping.

### Display & audio

| Part | Purpose | Est. Cost |
|------|---------|-----------|
| 1.69"/2.0" IPS LCD (ST7789 SPI) | Face animations | $5-8 |
| MAX98357A I2S DAC + amp | Audio output | $3-5 |
| Small speaker (28-36mm, 3W) | TTS playback, sound effects | $2-3 |

Display driven by Pico (same controller as servos/motors, zero-latency
sync for coordinated animations). Audio driven by Pi (TTS comes from backend
via WebSocket, plays directly on Pi).

### Sensors

| Part | Purpose | Est. Cost |
|------|---------|-----------|
| MPU-6050 | IMU — orientation, tap/shake detection | $2 |
| TSOP38238 IR receiver | Dock beacon detection | $1 |

### Power (robot)

| Part | Purpose | Est. Cost |
|------|---------|-----------|
| 18650 LiPo cells x4 (2S2P config) | Main battery — 7.4V, ~6800mAh | $12-20 |
| 2S BMS board (5A+ rated) | Cell balancing + protection | $3-5 |
| 2S balance charger module (2-3A) | Onboard charge controller | $5-8 |
| DC-DC buck converter (5V 3A) | Step down to Pi/Pico voltage | $3 |
| Voltage divider resistors (100K + 100K) | Battery ADC monitoring | $0.50 |
| Spring-loaded contacts/pogo pins x2 | Underside charging contacts | $3-5 |

### Charging dock

| Part | Purpose | Est. Cost |
|------|---------|-----------|
| IR LED + resistor | Dock homing beacon | $1 |
| Copper pads / pogo pin receptacles x2 | Dock-side charging contacts | $2-3 |
| 5V 2A USB power adapter | Dock power source | $3-5 |
| Small PCB or perfboard | Mount dock electronics | $1-2 |
| 3D-printed dock housing | Ramp + alignment walls | (print cost) |

### Wiring & connectors

| Part | Purpose | Est. Cost |
|------|---------|-----------|
| JST-SH 1.0mm connectors | Small sensor breakouts | $3 |
| JST-PH 2.0mm connectors | Battery, motors, speaker | $3 |
| JST-XH 2.5mm connectors | Higher current power paths | $3 |
| Pin headers 2.54mm (straight + right-angle) | GPIO, breakouts | $3 |
| Dupont crimp kit + tool (SN-28B or PA-09) | Custom jumpers | $15-20 |
| Screw terminals 5.08mm | Motor driver, dock pads | $2 |
| Silicone hookup wire 22-26 AWG (multi-color) | Flexible robot wiring | $8 |
| Heat shrink tubing assortment | Solder joint cleanup | $3 |
| M2/M2.5 brass standoff + screw kit | Board mounting | $8 |

### 3D printing

| Part | Purpose | Est. Cost |
|------|---------|-----------|
| Bambu Lab A1 Mini (or makerspace access) | Chassis, head, dock | ~$300 (one-time) |
| PLA filament 1kg | Robot body prints | $15-20 |

### Total estimated cost

**Parts only:** ~$170-210 (excluding Aksabot board and 3D printer)

**With printer:** ~$500 all-in

---

## What you're learning that's new

Aksabot taught: embedded C++, FreeRTOS, I2S audio, BLE, WebSocket, SPI display,
SDIO, NVS, OTA. The Cozmo build adds:

| Domain | Specifics |
|--------|-----------|
| Linux on hardware | systemd services, SSH, GPIO from Python, camera pipelines (libcamera/picamera2) |
| Computer vision | OpenCV, MediaPipe face detection, object tracking, ArUco markers |
| Motor control | PID loops, encoder feedback, differential drive kinematics |
| Pico SDK | C++ on RP2350, PIO state machines, PWM generation |
| Mechanical design | FreeCAD or Fusion 360, 3D printing, tolerances, servo mounts, cable routing |
| Power systems | Multi-voltage rails (7.4V motors, 5V Pi, 3.3V Pico), LiPo management, charge circuits |

The ST7789 face rendering on Pico is a C++ port of the Aksabot animation
logic — SPI driver code changes (ESP32 SPI API → Pico SDK), but the animation
state machine and frame logic carry over.

---

## The honest bottleneck: mechanical design

Software people entering robotics consistently underestimate mechanical design.
A wobbly servo mount ruins the expressiveness. Treads that slip make PID useless.
Parts that don't fit require 10-20 print iterations.

**A 3D printer is not optional for this build.** Options:

- **Bambu Lab A1 Mini** (~$300) — fast, reliable, good for PLA/PETG robot parts
- **Bambu Lab A1** (~$400) — same but bigger build plate (useful if chassis >180mm)
- **Local makerspace** — check for one in Jakarta
- **Print service** — viable for final parts, not for iteration

**Cable management is its own nightmare** inside a tight chassis. Plan for it
in CAD from day one — routing channels, strain relief points, connector access
for debugging. First-timers design a beautiful shell then realize they can't
physically plug in a USB cable.

---

## Power budget check

Four 18650s in 2S2P config (2 series, 2 parallel) = 7.4V nominal,
~6800mAh total, ~50Wh energy.

Rough active draw:
- Pi 4 with CV load: ~5-6W
- Motors (intermittent, driving): ~2-4W average
- Servos (intermittent): ~1-2W average
- Pico + display + sensors: ~1W
- Audio (intermittent): ~0.5W

**Total: ~10-13W active, ~5-6W idle**

Runtime estimate: **~3-4 hours active use**, ~8-10 hours idle.

Self-docking is still valuable for passive longevity, but the robot now has
enough capacity to run meaningful sessions without needing to retreat to the
dock constantly.

---

## Self-charging dock

### How it works

- **Dock has:** IR LED beacon pointed outward, two exposed copper pads for
  charging, 5V USB adapter feeding into the pads.
- **Robot has:** TSOP38238 IR receiver, two pogo pins on the underside, TP4056
  charge controller wired between contacts and battery.
- **Battery monitoring:** Pico reads battery voltage via ADC + voltage divider.
  Below threshold (e.g., 3.4V/cell), sends `battery:low` event up to Pi.

### Docking sequence

1. Pi receives `battery:low` event from Pico.
2. Pi triggers dock homing state: spin in place until IR beacon detected.
3. Pi drives robot toward beacon using IR signal strength.
4. (Optional) Camera detects ArUco marker on dock for final alignment.
5. Pi commands Pico to creep forward slowly until voltage rise confirms charging.
6. Robot enters sleep state, wakes when charged.

The "last 5cm" alignment is the tricky part — expect iteration on pad
placement and approach angle.

---

## What makes it feel like Cozmo (the real challenge)

The hardware is the easier problem. What made Cozmo feel alive was
**choreography** — face + head + treads + arm moving together with personality.

| Behavior | How it works |
|----------|-------------|
| Curious | Head tilts up + eyes widen + drives slowly forward a few cm |
| Frustrated | Head bobs down + arm slams + reverses |
| Happy | Bounces in place (quick forward/back pulses) + happy face |
| Thinking | Head tilts sideways + thinking dots + treads idle |
| Surprised | Quick backward jerk + wide eyes |
| Sleepy | Slow blink + head droops + drives to dock |

Your existing backend already emits `face:expression` per sentence. Extend it
to also emit `body:animate` with a choreography payload. The Pi forwards this
to the Pico, which executes the coordinated sequence locally (tight timing
between display, servos, and motors — no network round-trip per frame).

---

## Raspberry Pi model reference

| Model | CPU | RAM | Best for |
|-------|-----|-----|---------|
| Zero 2W | Quad-core 1GHz A53 | 512MB | Small IoT, size-constrained builds |
| 3B+ | Quad-core 1.4GHz A53 | 1GB | Legacy projects, media centers |
| 4B 4GB | Quad-core 1.8GHz A72 | 4GB | Base robot build |
| **4B 8GB** | Same | 8GB | **This build — headroom for extras** |
| 5 4GB | Quad-core 2.4GHz A76 | 4GB | NVMe storage, faster inference |
| 5 8GB | Same | 8GB | Local LLM inference on-device |
| Pico 2 | Dual-core M33 + RISC-V | 520KB SRAM | **Real-time motor control** |

Pico/Pico 2 run bare-metal or MicroPython — no Linux, no OS. Microcontrollers,
not computers.

---

## Build sequence

### Phase 1 — Pico 2 + motor control (start here)

**Before buying any other robot parts.**

Minimum shopping list: Pico 2, TB6612FNG, tank chassis with encoder motors,
breadboard, jumpers, 4xAA holder or single 18650. ~$35-40.

1. Write PID speed controller in C++ on Pico 2.
2. Get both motors driving straight using encoder feedback.
3. Make accurate turns (90°, 180°) using differential drive math.
4. Test UART communication (send commands over USB serial from laptop).

**Goal:** Reliable differential drive before anything else. De-risks the
most unfamiliar part of the build with ~$40 of parts.

### Phase 2 — Pi setup + backend integration

1. Buy Pi 4 8GB + camera + microSD.
2. Set up Pi OS, SSH, Python, systemd service for the robot process.
3. Write Python script: read camera frames, connect to NestJS backend.
4. Get comfortable with `picamera2`, async Python, WebSocket client.
5. Add UART link from Pi to Pico — Pi sends commands, Pico executes.

**Goal:** End-to-end: backend → Pi → Pico → motors move.

### Phase 3 — Servos and expressiveness

1. Add PCA9685 + MG90S servos + ST7789 display + MPU-6050 IMU.
2. Port Aksabot face rendering code from ESP32 to Pico (C++).
3. Write choreography primitives on Pico: `head_tilt(angle, speed)`,
   `arm_lift(angle)`, `bounce()`, `animate(emotion)`.
4. Trigger from backend `body:animate` events via Pi → UART → Pico.
5. Integrate IMU for tilt detection and straight-line correction.

**Goal:** Personality through coordinated movement, validated before chassis.

### Phase 4 — Audio + vision

1. Add MAX98357A I2S DAC + speaker to Pi.
2. Stream TTS audio from backend over WebSocket, play on Pi.
3. Add face detection (MediaPipe) — robot turns to face people.
4. Add obstacle detection via camera (or optional ultrasonic sensor).
5. Feed camera context to backend for richer AI responses.

**Goal:** Robot reacts to environment and speaks.

### Phase 5 — Design and print the body

1. Measure all components (Pi, Pico, motors, servos, battery, display).
2. Design in FreeCAD or Fusion 360 — plan cable routing from day one.
3. Print in iterations — expect 5-10 revision cycles.
4. Final assembly.

### Phase 6 — Self-charging dock

1. Design and print dock housing with alignment walls.
2. Wire IR beacon and charging pads.
3. Add pogo pins to robot underside, wire to TP4056 + battery.
4. Implement battery monitoring on Pico.
5. Implement homing sequence on Pi (IR signal tracking → final approach).
6. Tune the "last 5cm" alignment.

### Optional Phase 7 — Lift arm + cube picking

The lift arm is mechanically complex and least important for personality.
Treat as optional polish, not core build.

### Optional Phase 8 — CCTV streaming

Stream camera feed to Flutter companion app.
- **WebSocket MJPEG** — simplest, reuses existing WebSocket infrastructure.
- **RTSP** — lower latency, better efficiency, industry standard. Use
  `mediamtx` on Pi, `flutter_vlc_player` or `media_kit` in app.
- Add mode flag: `active` (robot personality) vs `surveillance` (streaming,
  motion alerts).

### Optional Phase 9 — Hardware acceleration

If face detection at 15-20 FPS isn't enough and you want real object
detection (YOLO, MobileNet) at 30+ FPS, add a **Google Coral USB Accelerator**
(~$30). Plugs into Pi 4 via USB, runs Edge TPU models. No architecture
changes needed.

Don't buy it upfront. Add when the base CV frame rate actually frustrates you.

---

## Reusing Aksabot's backend

The entire NestJS backend applies unchanged:

- STT → LLM → TTS pipeline — same
- Emotion tagging per sentence — same, now also drives body animations
- Memory system — same
- Scheduler (reminders, pomodoro, proactive events) — same
- WebSocket protocol — same, robot Pi connects as a new device

The robot is a new `device` in the database. The Flutter app manages it the
same way it manages Aksabot. Add a device type field to distinguish desk
companion vs mobile robot, but that's a minor backend addition.

---

## Cross-references

- [15-hardware-spec.md](15-hardware-spec.md) — Aksabot ES3C28P pin mapping (explains why camera can't be added)
- [16-hardware-capabilities.md](16-hardware-capabilities.md) — Untapped Aksabot capabilities
- [11-future-extensions.md](11-future-extensions.md) — Servo/mobility extensions originally scoped for Aksabot
- [01-architecture.md](01-architecture.md) — Ports and adapters pattern (reused in robot backend)
- [06-backend-api.md](06-backend-api.md) — WebSocket protocol the robot Pi will speak
