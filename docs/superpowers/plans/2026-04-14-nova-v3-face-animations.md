# Nova v3 Face Animations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade Aksa's Nova face style with Cozmo-inspired angled eye tops and proper arc mouths, delivering rich emotion from eye shape alone — no brows needed for most expressions.

**Architecture:** Two new `int8_t` fields (`tiltInner`, `tiltOuter`) are added to `ExprEyeStyle`. `drawEyeV2` applies them via a fillRoundRect body + fillTriangle wedge. Four Nova mouth cases are replaced with `thickBezier` arcs (already used by the Orbit style). All changes are backward-compatible with the Orbit style (which passes `tilt=0`).

**Tech Stack:** ESP-IDF / Arduino, LovyanGFX (fillRoundRect, fillTriangle, fillSmoothCircle, thickBezier already available), PlatformIO, C++17.

---

## File Map

| File | Change |
|------|--------|
| `firmware/include/face_style.h` | Add `tiltInner`/`tiltOuter` to `ExprEyeStyle` |
| `firmware/src/face_nova.cpp` | Update all 17 expression rows with tilt values + new squint tuning |
| `firmware/src/face_orbit.cpp` | Add `0, 0` for both new fields to every row (zero-change behaviour) |
| `firmware/src/display.cpp` | Extend `drawEyeV2` signature; apply tilt via triangle wedge; update 3 call sites; replace 5 Nova mouth cases with bezier arcs |

No new files. No header changes beyond `face_style.h`.

---

## Task 1: Add tilt fields to ExprEyeStyle

**Files:**
- Modify: `firmware/include/face_style.h:22-34`

- [ ] **Step 1: Add the two new fields to the struct**

Open `firmware/include/face_style.h`. The current `ExprEyeStyle` struct ends at line 34 with `bool hasBrows`. Add the two new fields directly after `hasBrows`:

```cpp
struct ExprEyeStyle {
    bool    useRoundRect;     ///< true = rounded rect (NOVA path), false = circle (ORBIT path)

    // ── Rounded rect params — used when useRoundRect = true ──────────────
    int16_t eyeW;             ///< Eye rectangle width in pixels
    int16_t eyeH;             ///< Eye rectangle height in pixels
    float   squintBase;       ///< Constant bottom-lid squint (0.0 = open, 1.0 = fully closed)
    float   squintAmpScale;   ///< Audio-reactive component: squint += mouthAmp * scale
    float   squintMax;        ///< Maximum total squint (0 = uncapped)
    float   driftDamp;        ///< Gaze drift multiplier: 1.0 = full drift, 0.0 = locked forward

    // ── Shared ────────────────────────────────────────────────────────────
    bool    hasBrows;         ///< Draw eyebrows for this expression (both styles)

    // ── Nova v3 top-lid tilt ──────────────────────────────────────────────
    // Positive = corner raised (visually higher on screen).
    // Inner = the side facing the nose. Left eye: right top. Right eye: left top.
    // Outer = the far side.              Left eye: left top. Right eye: right top.
    int8_t  tiltInner;        ///< Top inner corner offset in pixels (+raised/-lowered)
    int8_t  tiltOuter;        ///< Top outer corner offset in pixels (+raised/-lowered)
};
```

- [ ] **Step 2: Verify it compiles (struct size change is the only observable effect now)**

```bash
cd /Users/hendra/Projects/Others/Aksabot
pio run -e esp32s3 2>&1 | tail -20
```

Expected: build fails because `face_orbit.cpp` and `face_nova.cpp` initialiser lists are now short by two fields. That is expected — fixed in Task 2.

---

## Task 2: Update face_orbit.cpp and face_nova.cpp initialiser lists

**Files:**
- Modify: `firmware/src/face_orbit.cpp`
- Modify: `firmware/src/face_nova.cpp`

### Step 2a — face_orbit.cpp

The Orbit style never uses tilt (useRoundRect=false for every row). Add `0, 0` at the end of every row.

- [ ] **Replace the entire ORBIT definition:**

```cpp
#include "face_style.h"

// ── ORBIT — Classic circle eyes (v1) ─────────────────────────────────────────
//
// Original procedural style: white filled circles with a black pupil that drifts
// inside the iris. Organic, cartoon-like feel.
//
// useRoundRect = false for every expression — the renderer uses the EYES[] table
// in display.cpp for the per-expression circle dimensions. The only field that
// matters in this preset is hasBrows (and tilt is ignored for ORBIT).

const face_style::FaceStyleDef face_style::ORBIT = {
    /* name */ "orbit",
    /* id   */ face_style::StyleId::ORBIT,
    /* eyes */ {
        //                        useRR   W    H   sqBase sqAmp  sqMax  drift  brows  tIn tOut
        /* IDLE        */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false,  0,   0 },
        /* LISTENING   */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false,  0,   0 },
        /* THINKING    */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false,  0,   0 },
        /* SPEAKING    */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false,  0,   0 },
        /* CONFUSED    */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false,  0,   0 },
        /* SLEEPING    */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false,  0,   0 },
        /* OFFLINE     */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false,  0,   0 },
        /* ENCOURAGING */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, true,   0,   0 },
        /* CALM        */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false,  0,   0 },
        /* FOCUSED     */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false,  0,   0 },
        /* HAPPY       */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, true,   0,   0 },
        /* SAD         */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false,  0,   0 },
        /* SHRUG       */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, true,   0,   0 },
        /* SURPRISED   */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, true,   0,   0 },
        /* SHOCKED     */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false,  0,   0 },
        /* ANGRY       */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, true,   0,   0 },
        /* DISTURBED   */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false,  0,   0 },
    },
};
```

### Step 2b — face_nova.cpp

This is where the visual upgrade lives. Key design decisions:

- **ANGRY** `tiltInner=-12`: inner top corners drop sharply toward the nose → hard V-scowl without brows. Remove `hasBrows` (tilt replaces it).
- **SAD** `tiltInner=+10`: inner top corners rise toward the nose → classic puppy-eye frown.
- **FOCUSED** `tiltInner=-6`: mild V-tilt + squint → determined, no brows needed.
- **HAPPY** `tiltInner=+3, tiltOuter=+6, squintBase=0.50f`: outer top rises + bottom squints → D-shaped crescent eyes.
- **ENCOURAGING** `tiltInner=+4, tiltOuter=+2`: warm upward tilt; keep `hasBrows=false` now (tilt carries the expression).
- **CONFUSED** `tiltInner=-4, tiltOuter=+4`: one side slopes differently → subtle quizzical look.
- **SURPRISED** stays `hasBrows=true` (wide-open + raised brows = peak "wow" read).
- **LISTENING** size bumped to 78×44 for more attentive look.

- [ ] **Replace the entire NOVA definition:**

```cpp
#include "face_style.h"

// ── NOVA — Rounded rectangle eyes (v3) ───────────────────────────────────────
//
// Modern "screen character" style with Cozmo-inspired top-lid tilt.
// The tiltInner/tiltOuter fields angle the top edge of each eye so emotions
// read clearly from eye SHAPE alone — no eyebrows needed for most expressions.
//
// tiltInner > 0 : inner top corner raised  → SAD puppy look
// tiltInner < 0 : inner top corner lowered → ANGRY V-scowl
// tiltOuter > 0 : outer top corner raised  → HAPPY crescent (combine with squintBase)
//
// Eye dimensions for 240×320 ILI9341V with EYE_SPACE=48.

const face_style::FaceStyleDef face_style::NOVA = {
    /* name */ "nova",
    /* id   */ face_style::StyleId::NOVA,
    /* eyes */ {
        //                        useRR    W    H   sqBase sqAmp  sqMax  drift  brows  tIn tOut
        /* IDLE        */       { true,   68,  38,  0.00f, 0.00f, 0.00f, 1.00f, false,  0,   0 },
        /* LISTENING   */       { true,   78,  44,  0.00f, 0.00f, 0.00f, 1.00f, false,  0,   0 },
        /* THINKING    */       { true,   60,  30,  0.18f, 0.00f, 0.18f, 1.00f, false,  0,   0 },
        /* SPEAKING    */       { true,   68,  38,  0.00f, 0.30f, 0.30f, 0.25f, false,  0,   0 },
        /* CONFUSED    */       { true,   64,  36,  0.00f, 0.00f, 0.00f, 1.00f, false, -4,  +4 },
        /* SLEEPING    */       { true,    0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false,  0,   0 },
        /* OFFLINE     */       { true,    0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false,  0,   0 },
        /* ENCOURAGING */       { true,   76,  42,  0.08f, 0.00f, 0.08f, 0.50f, false, +4,  +2 },
        /* CALM        */       { true,   64,  36,  0.10f, 0.00f, 0.10f, 0.80f, false,  0,   0 },
        /* FOCUSED     */       { true,   58,  30,  0.28f, 0.00f, 0.28f, 0.30f, false, -6,   0 },
        /* HAPPY       */       { true,   72,  40,  0.50f, 0.25f, 0.75f, 0.00f, false, +3,  +6 },
        /* SAD         */       { true,   62,  34,  0.00f, 0.00f, 0.00f, 0.80f, false,+10,   0 },
        /* SHRUG       */       { true,   68,  38,  0.00f, 0.00f, 0.00f, 0.80f, false,  0,   0 },
        /* SURPRISED   */       { true,   82,  48,  0.00f, 0.00f, 0.00f, 0.50f, true,   0,   0 },
        /* SHOCKED     */       { true,   86,  52,  0.00f, 0.00f, 0.00f, 0.00f, false,  0,   0 },
        /* ANGRY       */       { true,   52,  28,  0.38f, 0.00f, 0.38f, 0.30f, false,-12,   0 },
        /* DISTURBED   */       { true,   68,  38,  0.00f, 0.00f, 0.00f, 1.00f, false,  0,   0 },
    },
};
```

- [ ] **Step 2c: Verify build compiles cleanly (the struct is now satisfied)**

```bash
cd /Users/hendra/Projects/Others/Aksabot
pio run -e esp32s3 2>&1 | tail -20
```

Expected: compiles successfully. The tilt fields exist in the data but `drawEyeV2` doesn't use them yet — visuals are unchanged at this point.

- [ ] **Step 2d: Commit**

```bash
cd /Users/hendra/Projects/Others/Aksabot
git add firmware/include/face_style.h firmware/src/face_nova.cpp firmware/src/face_orbit.cpp
git commit -m "feat(face): add tiltInner/tiltOuter fields to ExprEyeStyle, tune Nova v3 table"
```

---

## Task 3: Implement tilt in drawEyeV2

**Files:**
- Modify: `firmware/src/display.cpp` — `drawEyeV2` function (~line 239) and its three call sites (~lines 800–829)

The approach: the filled rounded-rect forms the body below the lower of the two corners. A single `fillTriangle` fills the raised wedge above it on whichever side is higher. This requires only two extra draw calls in the non-zero-tilt case.

**Coordinate system reminder:**
- Screen Y increases downward.
- `tiltLeft > 0` → left top corner is `tiltLeft` pixels HIGHER (smaller Y) than the base top.
- `tiltLeft < 0` → left top corner is `|tiltLeft|` pixels LOWER (larger Y) than the base top.

- [ ] **Step 3a: Replace the `drawEyeV2` function**

Find the existing `drawEyeV2` in `display.cpp` (starts around line 239, ends at line 268). Replace the entire function with:

```cpp
// V2/V3 eye — rounded rectangle style shared across expressions.
//
// scaleY      — blink scale (1=open, 0=closed)
// driftX/Y    — gaze drift: shifts the whole rect (no pupil)
// squintBot   — 0=flat bottom, 1=bottom lid fully risen
// eyeW/eyeH   — per-expression eye dimensions
// tiltLeft    — top-left corner offset px (+=raised, i.e. smaller screen Y)
// tiltRight   — top-right corner offset px (+=raised)
//
// For the left eye:  pass tiltLeft=tiltOuter, tiltRight=tiltInner
// For the right eye: pass tiltLeft=tiltInner, tiltRight=tiltOuter
static void drawEyeV2(LGFX_Sprite& s, int cx, int cy,
                      float scaleY, float driftX, float driftY,
                      float squintBot = 0.0f,
                      int eyeW = 68, int eyeH = 38,
                      int tiltLeft = 0, int tiltRight = 0) {
    static const int CR     = 8;
    static const int MAX_DX = 10;
    static const int MAX_DY = 5;
    static const uint16_t EYE_COL = rgb(218, 220, 230);

    int ox = constrain((int)driftX, -MAX_DX, MAX_DX);
    int oy = constrain((int)driftY, -MAX_DY, MAX_DY);
    int ex = cx + ox;
    int ey = cy + oy;

    // Half-heights driven by blink + squint
    int hhTop = (int)((eyeH / 2) * scaleY);
    int hhBot = (int)(hhTop * (1.0f - squintBot));
    int totalH = hhTop + hhBot;

    if (totalH < 2) {
        s.fillRoundRect(ex - eyeW / 2, ey - 1, eyeW, 2, 1, EYE_COL);
        return;
    }

    // Scale tilt with blink so the angled shape collapses naturally
    int tl = (int)(tiltLeft  * scaleY);
    int tr = (int)(tiltRight * scaleY);

    // Base top (flat, no tilt)
    int baseTop = ey - hhTop;
    // Actual per-corner tops — raised corner has smaller Y
    int leftTopY  = baseTop - tl;
    int rightTopY = baseTop - tr;
    int botY      = ey + hhBot;

    // Body: the rect that covers the region below the LOWER of the two corners
    int bodyTopY = max(leftTopY, rightTopY);

    int actualCR = CR;
    int bodyH = botY - bodyTopY;
    if (actualCR > hhBot)   actualCR = (hhBot  > 1) ? hhBot  - 1 : 1;
    if (actualCR > bodyH/2) actualCR = (bodyH/2 > 1) ? bodyH/2 - 1 : 1;

    s.fillRoundRect(ex - eyeW / 2, bodyTopY, eyeW, bodyH, actualCR, EYE_COL);

    // Wedge: fills the triangular raised area above bodyTopY on one side
    if (leftTopY < rightTopY) {
        // Left corner is higher — fill upper-left wedge
        // Triangle: apex=(ex-eyeW/2, leftTopY), base=(ex-eyeW/2, bodyTopY)→(ex+eyeW/2, bodyTopY)
        s.fillTriangle(ex - eyeW / 2, leftTopY,
                       ex - eyeW / 2, bodyTopY,
                       ex + eyeW / 2, bodyTopY,
                       EYE_COL);
    } else if (rightTopY < leftTopY) {
        // Right corner is higher — fill upper-right wedge
        s.fillTriangle(ex + eyeW / 2, rightTopY,
                       ex + eyeW / 2, bodyTopY,
                       ex - eyeW / 2, bodyTopY,
                       EYE_COL);
    }
}
```

- [ ] **Step 3b: Update the three `drawEyeV2` call sites in `renderFace`**

There are three places in `renderFace` that call `drawEyeV2`:

**Call site 1** — Nova OFFLINE (around line 800): two calls with hardcoded args, no tilt needed.
These already pass explicit `0.0f` squint and fixed dims. Leave them as-is — the new default parameters (`tiltLeft=0, tiltRight=0`) cover them automatically. No change needed here.

**Call site 2** — Nova DISTURBED asymmetric sizing (around line 828): the two main eye draw calls.
Find this block:
```cpp
drawEyeV2(s, leftEyeX,  eyeY, leftScale,  dx, dy, squint, lw, lh);
drawEyeV2(s, rightEyeX, eyeY, rightScale, dx, dy, squint, rw, rh);
```

Replace with (passing tilt mirrored between eyes):
```cpp
drawEyeV2(s, leftEyeX,  eyeY, leftScale,  dx, dy, squint, lw, lh,
           es.tiltOuter, es.tiltInner);
drawEyeV2(s, rightEyeX, eyeY, rightScale, dx, dy, squint, rw, rh,
           es.tiltInner, es.tiltOuter);
```

That is the only change needed for call site 2. The DISTURBED special-case (lines 824–826) adjusts `lw`/`lh`/`rw`/`rh` but those are local to the block — they still feed into the call correctly.

- [ ] **Step 3c: Build and confirm no errors**

```bash
cd /Users/hendra/Projects/Others/Aksabot
pio run -e esp32s3 2>&1 | tail -20
```

Expected: clean build, 0 errors, 0 warnings related to drawEyeV2.

- [ ] **Step 3d: Commit**

```bash
cd /Users/hendra/Projects/Others/Aksabot
git add firmware/src/display.cpp
git commit -m "feat(face): implement top-lid tilt in drawEyeV2 via fillTriangle wedge"
```

---

## Task 4: Replace Nova mouth cases with bezier arcs

**Files:**
- Modify: `firmware/src/display.cpp` — `drawMouth` function (~line 313)

**Coordinate convention (screen Y increases downward):**
- Smile: endpoints at same Y, control point BELOW (larger Y) → curve bows downward → opens downward → looks like a smile ✓
- Frown: endpoints at same Y, control point ABOVE (smaller Y) → curve bows upward → opens upward → looks like a frown ✓

Five cases to upgrade. All changes are inside `drawMouth`, inside their respective `if (nova)` branches only. The `else` branches (Orbit style) are untouched.

### Case A — IDLE resting mouth

Currently: a flat rounded-rect with subtle breathe oscillation.
Replace with: a very shallow smile arc (same feel, friendlier, matches Orbit style).

Find the `case face::Expression::IDLE:` branch, inside `} else {` (not-talking), inside `if (nova) {`. Replace that nova block:

```cpp
// Before:
if (nova) {
    float breathOff = sinf(breathPhase * 2 * 3.14159f) * 1.5f;
    int mw = 52, mh = 7 + (int)breathOff;
    if (mh < 5) mh = 5;
    s.fillRoundRect(CX - mw / 2, my - mh / 2, mw, mh, mh / 2, pal.mouth);
}

// After:
if (nova) {
    float breathOff = sinf(breathPhase * 2 * 3.14159f) * 1.5f;
    thickBezier(s, CX - 26, my + (int)breathOff,
                   CX,      my + 8 + (int)breathOff,
                   CX + 26, my + (int)breathOff,
                3, pal.mouth);
}
```

### Case B — HAPPY resting mouth

Currently: a flat wide rect with a white shine bar — looks like a shelf, not a smile.
Replace with: a wide arc smile (same bezier already used by the Orbit happy mouth).

Find `case face::Expression::HAPPY:`, inside `} else {` (not-talking), inside `if (nova) {`:

```cpp
// Before:
if (nova) {
    int mw = 54, mh = 8;
    s.fillRoundRect(CX - mw / 2, my + 4, mw, mh, mh / 2, pal.mouth);
    s.fillRoundRect(CX - mw / 2 + 6, my + 5, mw - 12, 3, 1,
                    blendRGB565(TFT_WHITE, pal.mouth, 160));
}

// After:
if (nova) {
    thickBezier(s, CX - 28, my,     CX, my + 18, CX + 28, my,     4, pal.mouth);
    thickBezier(s, CX - 18, my + 2, CX, my + 11, CX + 18, my + 2, 2,
                blendRGB565(TFT_WHITE, pal.mouth, 160), 16);
}
```

### Case C — SAD resting mouth

Currently: a narrow flat rounded-rect — looks identical to CALM or FOCUSED, no emotion.
Replace with: an arc frown (control point above endpoints).

Find `case face::Expression::SAD:`, inside `} else {` (not-talking), inside `if (nova) {`:

```cpp
// Before:
if (nova) {
    float trem = sinf(breathPhase * 6.28318f * 3) * 1.0f;
    int mw = 30, mh = 6;
    s.fillRoundRect(CX - mw / 2, my + 2 + (int)trem, mw, mh, mh / 2, pal.mouth);
}

// After:
if (nova) {
    float trem = sinf(breathPhase * 6.28318f * 3) * 1.5f;
    // Control point ABOVE endpoints → arc bows upward → frown
    thickBezier(s, CX - 22, my + 6 + (int)trem,
                   CX,      my - 4 + (int)trem,
                   CX + 22, my + 6 + (int)trem,
                3, pal.mouth);
}
```

### Case D — ENCOURAGING resting mouth

Currently: a flat "confidence bar" rect + shine — same problem as HAPPY resting.
Replace with: a smaller arc smile.

Find `case face::Expression::ENCOURAGING:`, inside `} else {` (not-talking), inside `if (nova) {`:

```cpp
// Before:
if (nova) {
    int mw = 48, mh = 8;
    s.fillRoundRect(CX - mw / 2, my + 4, mw, mh, mh / 2, pal.mouth);
    s.fillRoundRect(CX - mw / 2 + 5, my + 5, mw - 10, 3, 1,
                    blendRGB565(TFT_WHITE, pal.mouth, 120));
}

// After:
if (nova) {
    thickBezier(s, CX - 24, my,     CX, my + 14, CX + 24, my,     4, pal.mouth);
    thickBezier(s, CX - 15, my + 2, CX, my +  9, CX + 15, my + 2, 2,
                blendRGB565(TFT_WHITE, pal.mouth, 120), 14);
}
```

### Case E — ANGRY resting mouth

Currently: a flat horizontal rounded-rect — the frown reads as a straight line, not a clenched scowl.
Replace with: a tight inverted arc (frown) to match the Orbit style.

Find `case face::Expression::ANGRY:`, inside `} else {` (not-talking), inside `if (nova) {`:

```cpp
// Before:
if (nova) {
    int mw = 32, mh = 6;
    s.fillRoundRect(CX - mw / 2, my + 1, mw, mh, mh / 2, pal.mouth);
}

// After:
if (nova) {
    // Tight clenched frown — control above endpoints = arch upward = frown
    thickBezier(s, CX - 20, my + 4, CX, my - 4, CX + 20, my + 4, 3, pal.mouth);
    // Teeth-clenched highlight
    thickBezier(s, CX - 12, my + 4, CX, my - 1, CX + 12, my + 4, 1,
                blendRGB565(TFT_WHITE, pal.mouth, 100), 12);
}
```

- [ ] **Step 4b: Build clean**

```bash
cd /Users/hendra/Projects/Others/Aksabot
pio run -e esp32s3 2>&1 | tail -20
```

Expected: clean build.

- [ ] **Step 4c: Commit**

```bash
cd /Users/hendra/Projects/Others/Aksabot
git add firmware/src/display.cpp
git commit -m "feat(face): replace Nova resting mouths with bezier arcs (happy smile, sad frown, angry scowl)"
```

---

## Task 5: Final build verification

- [ ] **Step 5a: Full clean build**

```bash
cd /Users/hendra/Projects/Others/Aksabot
pio run -e esp32s3 -t clean && pio run -e esp32s3 2>&1 | tail -30
```

Expected: 0 errors, 0 warnings about new code.

- [ ] **Step 5b: Verify binary size is within partition limits**

From the build output, check the `.elf` section sizes. The app partition is 4MB (from `partitions.csv`). A typical binary for this project is ~1.5MB. The new code adds ~20 lines — negligible.

Expected: total flash usage well under 4MB.

- [ ] **Step 5c: Final commit if any cleanup needed, otherwise tag**

```bash
cd /Users/hendra/Projects/Others/Aksabot
git log --oneline -5
```

Expected: 3 commits from this feature (Tasks 2d, 3d, 4c) visible in recent history.

---

## Visual Design Reference

| Expression | tiltInner | tiltOuter | squintBase | Intended look |
|---|---|---|---|---|
| IDLE | 0 | 0 | 0 | Neutral friendly |
| LISTENING | 0 | 0 | 0 | Wide attentive |
| THINKING | 0 | 0 | 0.18 | Slightly droopy, ponderous |
| CONFUSED | -4 | +4 | 0 | Inner down, outer up — quizzical |
| FOCUSED | -6 | 0 | 0.28 | Mild V-tilt + squint — determined |
| HAPPY | +3 | +6 | 0.50 | Outer rises + bottom squints → crescent |
| ENCOURAGING | +4 | +2 | 0.08 | Warm upward tilt |
| SAD | +10 | 0 | 0 | Puppy eyes — inner corners raised sharply |
| ANGRY | -12 | 0 | 0.38 | Hard V-scowl — inner corners drop + squint |
| SURPRISED | 0 | 0 | 0 | Max open, brows on |
| SHOCKED | 0 | 0 | 0 | Max open, tremor |
| DISTURBED | 0 | 0 | 0 | Asymmetric size (handled in renderer) |

## Notes

- ORBIT style is completely unaffected — all tilt values are 0.
- `hasBrows` is removed from ANGRY and FOCUSING (tilt replaces them). `ENCOURAGING` drops brows too — the positive tilt carries the warmth. `SURPRISED` keeps brows.
- The `drawPeakBrows` path (energy-peak during speech) is preserved — it fires on top of any expression when amplitude spikes.
- The OFFLINE and SLEEPING special-case rendering paths bypass `drawEyeV2` entirely and are unaffected.
