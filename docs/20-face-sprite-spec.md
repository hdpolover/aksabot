# 20 — Aksa Face Sprite Specification

Design brief for creating Aksa's face sprite sheet. Hand this to a design agent.

---

## What we're building

Aksa is an AI desk companion living on a 2.8" touchscreen. His face is his primary communication channel — it reacts in real time to what he's saying and doing. We need a set of static expression frames that the ESP32 firmware will animate by stepping through them.

This is not a mascot. Aksa has edge. He's a gen-Z best friend, slightly unhinged, not corporate, not cute. Think "a face with personality" — not a cartoon pet.

---

## Technical output requirements

| Parameter | Value |
|-----------|-------|
| Canvas size per frame | **240 × 240 px** |
| Color mode | **RGB** (no transparency / no alpha) |
| Export format | **PNG** (one file per frame, named exactly as specified below) |
| Color depth | 24-bit RGB (will be converted to RGB565 for firmware) |
| Background | **#0D0D0D** (near-black — the display background color) |

Each frame is a standalone 240×240 PNG. Do not pack them into a grid — the conversion script handles that. Name each file exactly as specified in the frame list.

---

## Visual style

### Overall aesthetic

- **Minimalist.** Eyes + mouth only. No nose, no ears, no body. Just the face elements on a dark background.
- **Geometric but expressive.** Eyes are rounded rectangles or ovals. Not realistic, not pixel art — clean flat shapes with personality.
- **Light on dark.** Face elements are white/light colored against the dark background. Creates good contrast on the IPS display.
- **Slight edge.** Aksa is not soft and adorable. Eyes can be slightly asymmetric in confused/sarcastic expressions. Proportions can be slightly exaggerated.

### Layout on the 240×240 canvas

```
┌──────────────────────────┐
│                          │  ← 40px top margin
│    [LEFT EYE] [RIGHT EYE]│  ← Eyes centered vertically around y=100
│                          │  ← ~40px gap between eyes and mouth
│         [MOUTH]          │  ← Mouth centered around y=165
│                          │  ← 35px bottom margin
└──────────────────────────┘
```

- Eyes: each eye roughly 55×38 px, centered at x=75 and x=165, y=100
- Gap between eyes: ~35px
- Mouth: roughly 80px wide, centered at x=120, y=165

### Color palette

| Element | Color | Hex |
|---------|-------|-----|
| Background | Near-black | `#0D0D0D` |
| Eyes (default) | Soft white | `#E8E8E8` |
| Iris / pupil accent | Light blue-grey | `#B8D4E8` |
| Mouth | Soft white | `#E8E8E8` |
| Happy accent | Warm yellow-white | `#F5E6C8` |
| Sad accent | Muted blue | `#7A9BB5` |
| Thinking dots | Bright white | `#FFFFFF` |
| Offline / dim | Dark grey | `#444444` |

These are guidelines — a design agent can propose adjustments as long as the face reads clearly on a near-black background.

---

## Expression frames

### Naming convention

`{expression}_{frame_index}.png` — e.g., `idle_0.png`, `idle_1.png`, `happy_0.png`

Frame index starts at 0.

---

### `idle` — 4 frames (blink cycle)

Resting state. Eyes open, neutral expression. Frames animate a natural blink.

| Frame | Description |
|-------|-------------|
| `idle_0` | Eyes fully open. Rounded rectangle eyes, slight pupil in center. Mouth: gentle flat line with very slight upward curve at corners. |
| `idle_1` | Eyes 60% closed — top lid has dropped 60% of the way down. Mouth unchanged. |
| `idle_2` | Eyes fully closed — thin horizontal line, squished oval. Mouth unchanged. |
| `idle_3` | Eyes reopening — 60% open again (mirror of idle_1). Mouth unchanged. |

---

### `listening` — 2 frames

Alert. Eyes wide and bright. Used while recording / push-to-talk is active. Slight alternating glow to suggest attentiveness.

| Frame | Description |
|-------|-------------|
| `listening_0` | Eyes notably wider than idle — taller oval, brighter fill. Pupils larger. Mouth: neutral flat. |
| `listening_1` | Same but pupil slightly shifted toward center (attentive focus). Subtle brightness difference from frame 0. |

---

### `thinking` — 4 frames

Processing. Eyes half-closed. Animated dots appear below eyes (thinking indicator).

| Frame | Description |
|-------|-------------|
| `thinking_0` | Eyes 40% closed (relaxed squint). Mouth: no mouth — replaced by three small dots in a row at y=165. Dot 1 lit, dots 2+3 dim. |
| `thinking_1` | Same eyes. Dot 2 lit, dots 1+3 dim. |
| `thinking_2` | Same eyes. Dot 3 lit, dots 1+2 dim. |
| `thinking_3` | Same eyes. All three dots dim (pause frame). |

Dots: 3 circles, each ~10px diameter, spaced 18px apart, centered at x=120, y=165.

---

### `happy` — 4 frames (mouth cycle)

Genuinely pleased. Wide eyes, curved smile. Mouth animates as a talking cycle.

| Frame | Description |
|-------|-------------|
| `happy_0` | Eyes wide and bright (slightly larger than idle), warm accent tint. Mouth: wide curved smile, closed (crescent shape). |
| `happy_1` | Same eyes. Mouth: smile open slightly — thin gap, teeth or inner darkness visible. |
| `happy_2` | Same eyes. Mouth: smile open more — wider gap. |
| `happy_3` | Same eyes. Mouth: smile partially closed — between happy_0 and happy_1. |

---

### `sad` — 4 frames (mouth cycle)

Droopy eyes, downturned mouth. Muted blue accent tint.

| Frame | Description |
|-------|-------------|
| `sad_0` | Eyes: slightly smaller, inner corners drooped down (inner corner of eye lower than outer). Pupils small. Muted blue tint. Mouth: downward curve (frown), closed. |
| `sad_1` | Same eyes. Mouth: frown open slightly — small gap at center. |
| `sad_2` | Same eyes. Mouth: frown open more. |
| `sad_3` | Same eyes. Mouth: frown partially closed — between sad_0 and sad_1. |

---

### `excited` — 3 frames

High energy. Stars or sparkle in eyes, big grin. 

| Frame | Description |
|-------|-------------|
| `excited_0` | Eyes: large, wide open, bright. Small 4-point star shape or strong highlight flare in each eye. Mouth: wide open grin — tall oval, like a shout-laugh. |
| `excited_1` | Same eyes. Mouth slightly less open (mid-grin). |
| `excited_2` | Same eyes. Mouth at widest — peak open. |

---

### `calm` — 2 frames

Soft and steady. Relaxed eyes, gentle neutral mouth.

| Frame | Description |
|-------|-------------|
| `calm_0` | Eyes: slightly softer/rounder than idle, less contrast, gentle look. Mouth: neutral flat line, extremely slight upward curve — barely a smile. |
| `calm_1` | Very slight mouth shape change — lower jaw drops ~5px, suggesting slow speech. Eyes unchanged. |

---

### `focused` — 4 frames (talking cycle)

Locked in. Eyes slightly narrowed/squinted, tight speaking mouth.

| Frame | Description |
|-------|-------------|
| `focused_0` | Eyes: slightly narrowed — 75% of normal height, pupils centered. Alert but calm. Mouth: tight flat line (closed). |
| `focused_1` | Same eyes. Mouth: tiny opening — small horizontal slit, 30px wide. |
| `focused_2` | Same eyes. Mouth: slightly wider slit, 50px wide. |
| `focused_3` | Same eyes. Mouth: back to tiny opening. |

---

### `confused` — 3 frames

Asymmetric — one eye slightly higher than the other, giving a puzzled tilt effect.

| Frame | Description |
|-------|-------------|
| `confused_0` | Left eye: normal position. Right eye: 8px higher than normal, slightly smaller. Mouth: one corner up, one corner flat (asymmetric). |
| `confused_1` | Same offset eyes. Mouth shifts — previously raised corner now drops, other corner rises. |
| `confused_2` | Eyes return closer to level but right eye still 4px high. Mouth: uncertain flat line. |

---

### `sleeping` — 3 frames (slow cycle)

Fully closed, peaceful breathing.

| Frame | Description |
|-------|-------------|
| `sleeping_0` | Eyes: closed thin lines (very slim horizontal ellipses). Mouth: tiny soft smile curve, barely visible. Small `z z` text or symbol in upper right area of canvas (optional, small, dim). |
| `sleeping_1` | Eyes: same closed lines but slightly lower position (2-3px) suggesting relaxed face. Mouth unchanged. |
| `sleeping_2` | Eyes: same. Slightly lighter fill on eyes (subtle glow-pulse effect suggesting breathing). Mouth unchanged. |

---

### `offline` — 2 frames

Dim, flat. Backend not connected.

| Frame | Description |
|-------|-------------|
| `offline_0` | Eyes: dark grey fill (`#444444`), no pupils — flat blank ovals. Mouth: flat dim line. Very low contrast overall. |
| `offline_1` | Eyes: slightly dimmer/darker than offline_0 (slow blink/pulse). Mouth unchanged. |

---

### `encouraging` — 3 frames

Bright and welcoming. Eyebrows up (if the style includes eyebrows — otherwise extra-wide eyes). Big open smile.

| Frame | Description |
|-------|-------------|
| `encouraging_0` | Eyes: very wide, bright. If eyebrows exist: both raised high. Mouth: big open smile, slightly less extreme than excited. |
| `encouraging_1` | Same eyes. Mouth: open slightly less. |
| `encouraging_2` | Same eyes. Mouth at widest open. |

---

### `shrug` — 2 frames

Resigned, tilted. Used for errors and ambiguous states.

| Frame | Description |
|-------|-------------|
| `shrug_0` | Entire face elements tilted ~5° clockwise. Left eye slightly higher. Mouth: one side up, one side flat — sideways uncertain expression. |
| `shrug_1` | Face elements tilted ~5° counter-clockwise (rock back the other way). |

---

## Frame summary

| Expression | Frames | Files |
|------------|--------|-------|
| `idle` | 4 | `idle_0` – `idle_3` |
| `listening` | 2 | `listening_0` – `listening_1` |
| `thinking` | 4 | `thinking_0` – `thinking_3` |
| `happy` | 4 | `happy_0` – `happy_3` |
| `sad` | 4 | `sad_0` – `sad_3` |
| `excited` | 3 | `excited_0` – `excited_2` |
| `calm` | 2 | `calm_0` – `calm_1` |
| `focused` | 4 | `focused_0` – `focused_3` |
| `confused` | 3 | `confused_0` – `confused_2` |
| `sleeping` | 3 | `sleeping_0` – `sleeping_2` |
| `offline` | 2 | `offline_0` – `offline_1` |
| `encouraging` | 3 | `encouraging_0` – `encouraging_2` |
| `shrug` | 2 | `shrug_0` – `shrug_1` |
| **Total** | **40 frames** | |

---

## Delivery

- 40 PNG files, each 240×240 px, RGB (no alpha), named exactly as listed above
- Background: `#0D0D0D` on every frame (not transparent)
- Delivered in a flat folder (no subfolders) — the conversion script will pack them

---

## Conversion pipeline (after delivery)

The designer does not need to handle this — documented here for context.

After the PNGs are delivered, a Python script will:
1. Validate all 40 files exist and are 240×240
2. Convert each PNG to RGB565 BMP
3. Pack into a single `sprite_sheet.bmp` (4-column grid, 10 rows of 240px each)
4. Generate `sprite_manifest.h` with frame lookup table for firmware

The firmware reads the sprite sheet from SD into PSRAM on boot, then blits frames by index using `tft.pushImage()`.
