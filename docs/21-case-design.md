# 21 — Case Design: 3D-Printed TV Case

> Hardware reference: [15-hardware-spec.md](15-hardware-spec.md)
> Board: ES3C28P — 50mm × 86mm × 5.6mm, ESP32-S3 N16R8

---

## 1. Concept

A compact desktop case shaped like a retro CRT television. Simple silhouette,
no over-engineering. The 2.8" portrait display (43.2 × 57.6mm) naturally fits
a 4:3 CRT proportion. Key aesthetic touches: fat bezel, stubby antenna, side
dials, power LED window, and a rear speaker grille.

---

## 2. Before You Model Anything — Measure These

The spec gives PCB outer dimensions and mounting hole spacing. Component
positions on the short edges are not dimensioned in the spec and must be
measured from your physical board.

**Required measurements (grab a caliper):**

| What | How to measure | Used for |
|------|---------------|---------|
| USB-C center from left inner edge | From left side of the 50mm edge to center of USB-C port | Top wall cutout position |
| RESET button center from left inner edge | Same edge, to center of button dome | Top wall pinhole position |
| BOOT button center from left inner edge | Same edge, to center of button dome | Top wall hole position |
| USB-C port height | Measure the physical connector height | Top wall slot height |
| MicroSD slot center from left inner edge | Bottom 50mm edge, to center of SD slot opening | Back wall slot position |
| MicroSD slot height | Physical slot opening height | Back wall slot height |
| RGB LED center (X, Y from corner) | Back of PCB, top-right area | Light pipe alignment |
| MIC position (X, Y from corner) | Back of PCB, bottom-left area (board is 180° rotated in case) | Mic hole position |

> **Note:** With the board mounted 180° rotated (USB-C edge facing up), what
> was originally the top-right of the board becomes the bottom-left inside the
> case. Mic holes go on the bottom-left of the back shell.

---

## 3. Board Orientation Inside the Case

The board is mounted **180° rotated** relative to its natural portrait
orientation. This puts USB-C, RESET, and BOOT on the top edge of the case.

```
CASE TOP
┌────────────────────────────────────────┐
│  [BOOT]    [USB-C slot]    [RESET]     │  ← top wall, 50mm edge
│                                        │
│         ┌──────────────────┐           │
│         │                  │           │
│         │   DISPLAY FACE   │           │
│         │  (portrait, fw   │           │
│         │   rotation fix)  │           │
│         │                  │           │
│         └──────────────────┘           │
│  [antenna top-right]                   │
│  [LED window bottom-right]             │
│  [side dials on right wall]            │
│                                        │
│  ┌────┐                        ┌────┐  │
└──┤FOOT├────────────────────────┤FOOT├──┘
   └────┘                        └────┘
CASE BOTTOM
```

**Consequence:** The display renders upside-down. Fix with a one-line change in
firmware — see Section 9.

---

## 4. Overall Case Dimensions

| Dimension | Value | Derivation |
|-----------|-------|-----------|
| Outer width | 62mm | 50mm PCB + 3mm wall × 2 + 3mm bezel overhang × 2 |
| Outer height (body) | 106mm | 86mm PCB + 10mm top wall + 6mm bottom wall |
| Total height with feet | ~118mm | Body + 12mm feet |
| Outer depth | 20mm | 2mm front + 5.6mm PCB + 8mm battery gap + 2mm back |
| General wall thickness | 2.5mm | Structural minimum for FDM |
| Front face thickness | 2mm | Bezel face plate |
| Top wall thickness | 3mm | Thicker — USB-C slot cuts through it |

---

## 5. Front Shell

### 5.1 Display Cutout

The cutout uses a two-step recess so the touch glass sits cleanly.

| Step | Dimensions | Depth | Purpose |
|------|-----------|-------|---------|
| Outer step | 44.7mm × 59.1mm | 1mm | Seats the touch glass edge |
| Inner aperture | 43.2mm × 57.6mm | Through | Display active area |

- Corner radius: 1mm on inner aperture, 1.5mm on outer step
- Centered horizontally on the front face
- Centered vertically with ~6mm bezel top/bottom, ~7mm bezel sides

### 5.2 Bezel Face

- Outer corner radius: 4mm
- Very slight convex bow at center (0.5mm, optional) — mimics CRT glass curvature
- 1° forward draft angle on the face plate (optional, subtle CRT taper)

### 5.3 Power LED Window

- Shape: 5mm diameter circle
- Position: front bezel, bottom-right — 8mm from right edge, 8mm from bottom edge
- Function: light pipe from WS2812B RGB LED on the back of PCB
- The RGB LED breathes green (idle), blue (listening), etc. — looks like a TV power light

### 5.4 Light Pipe Channel

- 4mm round channel running from the LED window on the front face through
  to the RGB LED position on the PCB back
- Measure the LED position from Step 2 before modeling this channel
- Can be left hollow or filled with clear filament / hot glue after assembly

---

## 6. Top Wall — Port Cutouts

All three items (BOOT, USB-C, RESET) are on the same 50mm short edge.
Left-to-right order when viewing the front:

```
LEFT ──── [BOOT hole] ── [USB-C slot] ── [RESET pinhole] ──── RIGHT
```

| Component | Cutout shape | Approx position | Notes |
|-----------|-------------|-----------------|-------|
| BOOT | 4mm round | ~8mm from left inner wall | Recessed button cap or bare hole |
| USB-C | 10mm × 4mm rect | ~21mm from left (centered) | Chamfer entry edges |
| RESET | 3mm round | ~38mm from left | Pinhole only — paperclip access |

> These positions are approximate. Use your caliper measurements from Section 2
> to get exact X positions.

**USB-C slot detail:**
- Width: measure your board's USB-C connector width + 0.5mm clearance
- Height: measure connector height + 0.3mm clearance (typically 10mm × 4mm)
- Chamfer the entry edges 0.5mm so the cable plugs in easily
- Top wall is 3mm thick here for rigidity

**BOOT button:**
- Option A: bare 4mm hole — press with a pen tip
- Option B: print a small push cap that sits flush and clicks through the hole
- Option B looks cleaner for a finished product

---

## 7. Side Walls

### Left wall
No port cutouts. Smooth. 2.5mm thick.

### Right wall
Decorative dials only (no functional cuts).

| Feature | Spec |
|---------|------|
| Dial count | 2 |
| Dial shape | Cylinder, 10mm diameter, 4mm proud of wall surface |
| Dial spacing | 18mm apart vertically, centered on wall height |
| Dial position | Centered on right wall horizontally |

The lower dial can be hollowed and fitted with a push-through cap wired to a
spare GPIO button in the future (GPIO2/3/14/21 are broken out on the expand
header). For now, decorative.

---

## 8. Bottom Wall & Feet

| Feature | Value |
|---------|-------|
| Bottom wall thickness | 4mm |
| Foot width | 14mm |
| Foot depth | 10mm |
| Foot height | 12mm |
| Foot profile | Slight outward trapezoid flare — wider at base |
| Foot inset from outer edge | 4mm each side |
| Foot corner radius | 2mm |

Feet provide ~12mm desk clearance. This is important — the MIC holes on the
back need airflow, and the feet keep the case from sitting flat against the
desk and muffling sound.

No port cutouts on the bottom wall. Battery, UART, and the other bottom-edge
headers are all internal permanent connections.

---

## 9. Back Shell

### 9.1 MicroSD Slot

| | Value |
|---|---|
| Position | Bottom-right area of back wall (board is 180° rotated — SD is on the bottom edge) |
| Cutout width | Measure from board + 0.5mm clearance (typically ~15mm) |
| Cutout height | Measure from board + 0.3mm clearance (typically ~2.5mm) |
| Wall inset | Flush with back wall outer face |

Access is occasional (TTS cache, log retrieval, OTA images). No door needed —
bare slot is fine.

### 9.2 Microphone Holes

The MEMS mic is downward-facing (opens toward the back of the PCB). With the
board mounted 180° rotated, the mic sits at the **bottom-left corner of the
back**.

| | Value |
|---|---|
| Hole count | 3 |
| Hole diameter | 2mm each |
| Pattern | Triangle or row, spaced 4mm apart |
| Position | Bottom-left quadrant of back shell, aligned to mic component |

Measure the exact mic position from Step 2 before placing these holes.

### 9.3 Speaker Pocket & Grille

The board has a 1.25mm 2P speaker header. You supply the speaker and wire it
internally.

**Recommended speaker:** 28mm round, 8Ω, ≤1.5W

| | Value |
|---|---|
| Pocket shape | 30mm diameter circle |
| Pocket depth | 3mm recess into back wall |
| Grille pattern | 7× horizontal slots inside pocket |
| Each slot | 18mm wide × 1.2mm tall, 2mm vertical spacing |
| Speaker mount | Press-fit or 2-part snap ring around speaker rim |

Position the speaker pocket in the **lower-center of the back**, below the PCB
area. Leave 5mm clearance from the MicroSD slot.

### 9.4 Antenna

| | Value |
|---|---|
| Shape | Cylindrical stub |
| Diameter | 6mm |
| Height above case | 35mm |
| Position | Top-right corner of back shell, 4mm from each outer edge |
| Base | Slight fillet where it meets the case body |

Non-functional. Can be printed as part of the back shell or as a separate
press-fit piece (easier to print without supports).

---

## 10. Internal Layout

```
         BACK SHELL (view from inside)
┌──────────────────────────────────────────────┐
│  [I2C header] [Expand header]                │← these face up (top short edge)
│  [Speaker header] [RGB LED]                  │  internal, wire routes to speaker
│                                              │
│  ╔══════════════════════════════╗            │
│  ║         PCB BACK             ║            │
│  ║  (board mounted 180° rot.)   ║            │
│  ╚══════════════════════════════╝            │
│     M3 standoffs at 42×78mm spacing          │
│                                              │
│  [Battery] ←── velcro/tape to back wall      │
│  (fits in 8mm gap behind PCB)                │
│                                              │
│  [BAT header] [UART] [MicroSD]               │← bottom short edge
└──────────────────────────────────────────────┘
```

### PCB Standoffs

| | Value |
|---|---|
| Pattern | 42mm × 78mm (from spec sheet) |
| Hole diameter | 3.5mm (M3) |
| Standoff height | 2mm printed post |
| Fastener | M3 × 6mm screw + M3 brass heat insert (recommended) or self-tapping M3 |
| Count | 4 corners |

### Battery

| | Value |
|---|---|
| Recommended capacity | 1000mAh |
| Typical size | 50mm × 34mm × 6mm |
| Mounting | Double-sided tape or velcro strip to back wall inner face |
| Fits in gap | 8mm gap behind PCB — 6mm battery leaves 2mm clearance |
| Connection | Short wire to BAT header on board bottom edge |

> Battery polarity warning: the BAT header is 1.25mm 2P — verify polarity
> before connecting. Reversed polarity will damage the charging IC.

---

## 11. Two-Part Assembly

The case splits front + back. No top/bottom split — the top wall (ports) is
part of the front shell for rigidity.

```
FRONT SHELL contains:          BACK COVER contains:
- Bezel face plate             - Speaker pocket + grille
- All four side walls          - MicroSD slot cutout
- Top wall (port cutouts)      - Mic holes
- Bottom wall + feet           - Antenna stub
- PCB standoffs                - Battery velcro surface
- Light pipe channel
```

**Joining method:**
- 2× M3 screws at bottom corners (through back cover into heat inserts in front shell)
- No screws on top — the port cutouts register the top edge
- Optional: snap clips on left/right walls for tool-free open, with screws as backup

**Print orientation recommendation:**
- Front shell: print face-down (display opening faces build plate). No supports needed for the display recess.
- Back cover: print exterior-face-down. Speaker pocket and grille slots print cleanly without supports.

---

## 12. Firmware Change Required

Mounting the board 180° rotated means the display renders upside-down.
Fix with a rotation setting in `firmware/include/lgfx_config.h`:

```cpp
// Change display rotation to 180°
// In your LovyanGFX panel config, find setRotation and change:
cfg.panel_cfg.offset_rotation = 2;  // 0=0°, 1=90°, 2=180°, 3=270°
```

Or wherever `setRotation()` is called in the display init — pass `2` for 180°.

Touch coordinates will also be mirrored. In the FT6336G touch config:
```cpp
cfg.touch_cfg.offset_rotation = 2;  // match display rotation
```

Test by running the boot screen after the change and confirming the display
and touch both work correctly before final assembly.

---

## 13. Print Settings

| Setting | Value |
|---------|-------|
| Layer height | 0.15mm (detail) or 0.2mm (speed) |
| Wall perimeters | 4 |
| Infill | 20–25%, gyroid or grid |
| Top/bottom layers | 5 |
| Material | PLA (fine for desk use) or PETG (slightly more heat-tolerant) |
| Supports | None if printed in recommended orientations |
| Tolerances (mating surfaces) | 0.2mm clearance on all fits |
| Tolerances (display cutout) | 0.5mm extra on all sides beyond active area |
| Port cutouts | Add 0.3–0.5mm clearance beyond measured component size |

---

## 14. Assembly Order

1. Print front shell and back cover
2. Install M3 brass heat inserts into front shell standoff posts (soldering iron)
3. Route speaker wire through internal channel, solder/connect to speaker
4. Connect battery to BAT header (verify polarity first)
5. Mount PCB to standoffs with M3 × 6mm screws (4 corners, 42×78mm pattern)
6. Feed speaker wire to board's 1.25mm 2P speaker header
7. Optionally fill light pipe channel with clear hot glue for better light diffusion
8. Snap/screw back cover onto front shell
9. Flash firmware with display rotation fix (Section 12)
10. Test display, touch, audio, buttons, and LED through the case

---

## 15. Cross-References

- [15-hardware-spec.md](15-hardware-spec.md) — Full PCB spec, pin mapping, exact dimensions
- [16-hardware-capabilities.md](16-hardware-capabilities.md) — Expansion opportunities (servos, sensors via spare GPIO)
- [05-firmware.md](05-firmware.md) — Display, touch, audio, LED firmware modules
- [13-first-setup.md](13-first-setup.md) — First boot after assembly
