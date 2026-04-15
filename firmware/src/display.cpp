#include "display.h"
#include "face.h"
#include "face_style.h"
#include "config.h"
#include "lgfx_config.h"
#include <Arduino.h>
#include <SD_MMC.h>
#include <cmath>

// Pre-allocated sprite buffer from main.cpp (allocated before WiFi eats PSRAM)
void* preallocSpriteBuffer = nullptr;

// ── Internal state ─────────────────────────────────────
static display::Mode currentMode = display::Mode::FACE;
static display::Mode previousMode = display::Mode::FACE;
static display::StatusBar statusBar = {};
static display::PomodoroData pomodoroData = {};
static display::ReminderData reminderData = {};
static display::CountdownData countdownData = {};

static display::GlanceData glanceData = {};
static display::GlanceData latestContext = {};
static bool contextDataAvailable = false;

// ── Live clock state (seeded by context:sync, ticks locally) ──
static uint32_t syncedMinutes = 0;  // total minutes since midnight at last sync
static uint32_t syncedAtMs    = 0;  // millis() captured at sync time

static bool sleeping = false;
static uint8_t brightness = 70;       // Current/target brightness for the HW
static uint8_t userBrightness = 70;   // User-set brightness (survives sleep)
static bool transcriptEnabled = false;
static char transcriptText[384] = {};

// BIOS overlay — baked into the sprite each frame before push (flicker-free)
static struct {
    bool    enabled = false;
    char    title[32]  = {};
    char    counter[12] = {};
    char    navL[16]   = {};
    char    navC[16]   = {};
    char    navR[16]   = {};
} g_biosOverlay;

// Transcript auto-scroll state
static int  transcriptScrollLine     = 0;   // first visible line index
static int  transcriptTotalLines     = 0;   // total wrapped lines (updated by renderer)
static uint32_t transcriptScrollMs   = 0;   // last scroll-advance timestamp
static const uint32_t TRANSCRIPT_SCROLL_INTERVAL_MS = 2500;

// Text response mode (full-screen text when TTS is disabled)
static char     textResponseBuf[1024]  = {};
static bool     textResponseComplete   = false;
static uint32_t textResponseCompleteMs = 0;
static const uint32_t TEXT_RESPONSE_LINGER_MS = 8000;   // auto-return after 8s
static float    textScrollPx           = 0.0f;           // current scroll offset (px)
static uint32_t textScrollLastMs       = 0;              // for delta-time scroll anim
static const float TEXT_SCROLL_SPEED   = 40.0f;         // px per second

// Auto-return timer
static bool autoReturnActive = false;
static uint32_t autoReturnAtMs = 0;

// Rendering rate control
static uint32_t lastRenderMs = 0;
static const uint16_t RENDER_INTERVAL_MS = 33;  // ~30fps

// Clock dirty flag — set when entering CLOCK mode so the first frame always draws
static bool g_clockDirty = true;

// Fade transition state
static bool fadeActive = false;
static uint8_t fadeFrom = 0;
static uint8_t fadeTo = 0;
static uint32_t fadeStartMs = 0;
static uint16_t fadeDurationMs = 0;

// ── LovyanGFX display driver ─────────────────────────
LGFX tft;  // Non-static: shared with touch.cpp via extern
static LGFX_Sprite sprite(&tft);

// Legacy colors (for non-face modes)
static const uint16_t COL_BG        = TFT_BLACK;
static const uint16_t COL_FACE      = TFT_WHITE;
static const uint16_t COL_ACCENT    = TFT_CYAN;
static const uint16_t COL_ERROR     = TFT_RED;
static const uint16_t COL_CALM      = TFT_GREEN;
static const uint16_t COL_WARM      = TFT_YELLOW;
static uint16_t COL_DIM;
static uint16_t COL_STATUS_BG;

static const int CX = LCD_WIDTH / 2;
static const int CY = LCD_HEIGHT / 2 - 20;
static const int EYE_SPACE = 48;
static const int MOUTH_Y   = CY + 70;

// ── Home mode — what the display returns to after wake/dismiss ────────────
static display::Mode g_homeMode = display::Mode::FACE;

// ── Mode-change callback ───────────────────────────────────────────────────
static display::ModeChangeCallback g_onModeChange = nullptr;

void display::setOnModeChange(ModeChangeCallback cb) {
    g_onModeChange = cb;
}

static const char* modeToString(display::Mode m) {
    switch (m) {
        case display::Mode::FACE:      return "face";
        case display::Mode::CLOCK:     return "clock";
        case display::Mode::POMODORO:  return "pomodoro";
        case display::Mode::REMINDER:  return "reminder";
        case display::Mode::COUNTDOWN: return "countdown";
        case display::Mode::STATUS:    return "status";
        case display::Mode::GLANCE:         return "glance";
        case display::Mode::IMAGE:          return "image";
        case display::Mode::TEXT_RESPONSE:  return "text_response";
        default:                            return "face";
    }
}

// ── Active face style ─────────────────────────────────
// Points to one of the built-in presets (ORBIT or NOVA).
// Changed at runtime via display::setFaceStyle() — loaded from NVS on boot.
static const face_style::FaceStyleDef* g_faceStyle = &face_style::NOVA;

// ── Runtime face color overrides ──────────────────────
// Changed via display::setFaceColors() — loaded from NVS on boot.
// bgColor: 24-bit RGB background (0xRRGGBB). Replaces pal.bg for all expressions.
// eyeBody565: RGB565 eye fill — used for NOVA rectangles and ORBIT sclera.
// Default eyeBody is rgb(218,220,230) = 0xDEFC in RGB565.
static uint32_t g_faceBgColor    = 0x000000u;
static uint16_t g_faceEyeBody565 = 0xDEFCu;  // rgb(218,220,230)
static uint16_t g_faceMouth565   = 0xFFFFu;  // rgb(255,255,255) — default white mouth

// ── Rich color system (from face-animations firmware) ─────

static inline uint16_t rgb(uint8_t r, uint8_t g, uint8_t b) {
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

static uint16_t blendRGB565(uint16_t fg, uint16_t bg, uint8_t alpha) {
    uint16_t fr = (fg >> 11), ffg = (fg >> 5) & 0x3F, fb = fg & 0x1F;
    uint16_t br = (bg >> 11), bbg = (bg >> 5) & 0x3F, bb = bg & 0x1F;
    uint16_t r = (fr * alpha + br * (255 - alpha)) / 255;
    uint16_t g = (ffg * alpha + bbg * (255 - alpha)) / 255;
    uint16_t b = (fb * alpha + bb * (255 - alpha)) / 255;
    return (r << 11) | (g << 5) | b;
}

// ── Clock-mode cat + mouse mascots ───────────────────────────────────────────

// Shared arena bounds (screen minus a small margin)
static constexpr int ARENA_X0 = 15, ARENA_X1 = 225;
static constexpr int ARENA_Y0 = 20, ARENA_Y1 = 309;

enum class CatBehavior : uint8_t { WALK, SIT, LOOK_UP, PAW_UP, CHASE };

struct CatState {
    float    x = 60.0f, y = 260.0f;
    float    tx = 60.0f, ty = 260.0f;
    int8_t   facing = 1;
    CatBehavior behavior = CatBehavior::SIT;
    uint8_t  frame        = 0;
    uint8_t  tailPhase    = 0;
    uint8_t  behaviorTicks = 0;
    uint8_t  victoryTicks  = 0;   // PAW_UP frames held after a catch
    uint32_t lastMs       = 0;
};

struct MouseState {
    float   x  = 0.0f, y = 0.0f;
    float   vx = 0.0f, vy = 0.0f;  // velocity (px / tick)
    int8_t  facing  = 1;
    uint8_t frame   = 0;
    uint8_t tailPhase = 0;
    bool    active  = false;
    uint8_t dirChangeTicks = 0;  // countdown to next random swerve
    int     spawnCountdown = 0;  // ticks until next spawn attempt (0 = spawn now)
};

static CatState  g_cat;
static MouseState g_mouse;
static bool       g_catInited = false;

// Returns value in [lo, hi]
static inline int catRand(int lo, int hi) {
    return lo + (int)(esp_random() % (uint32_t)(hi - lo + 1));
}

// ── Mouse helpers ──────────────────────────────────────────────────────────

// Mouse always runs — base speed is 4.2px/tick, panics to 5.8 when cat is close.
// Cat chase speed is 5.2px/tick — faster than mouse base but mouse zigzags.
static constexpr float MOUSE_SPEED_BASE  = 4.2f;
static constexpr float MOUSE_SPEED_PANIC = 5.8f;
static constexpr float CAT_CHASE_SPEED   = 5.2f;
static constexpr float CAT_WALK_SPEED    = 2.5f;
static constexpr float PANIC_DIST        = 60.0f;  // cat distance that triggers panic

// Spawn the mouse at a random arena edge, immediately running inward
static void mouseSpawn() {
    int edge = catRand(0, 3);
    switch (edge) {
        case 0: g_mouse.x = (float)catRand(ARENA_X0, ARENA_X1); g_mouse.y = (float)ARENA_Y0; break;
        case 1: g_mouse.x = (float)catRand(ARENA_X0, ARENA_X1); g_mouse.y = (float)ARENA_Y1; break;
        case 2: g_mouse.x = (float)ARENA_X0; g_mouse.y = (float)catRand(ARENA_Y0, ARENA_Y1); break;
        default: g_mouse.x = (float)ARENA_X1; g_mouse.y = (float)catRand(ARENA_Y0, ARENA_Y1); break;
    }
    // Head toward arena center with some randomness — always at full run speed
    float dx = (ARENA_X0 + ARENA_X1) / 2.0f - g_mouse.x + (float)catRand(-25, 25);
    float dy = (ARENA_Y0 + ARENA_Y1) / 2.0f - g_mouse.y + (float)catRand(-12, 12);
    float d  = sqrtf(dx * dx + dy * dy);
    g_mouse.vx = (d > 0) ? (dx / d) * MOUSE_SPEED_BASE : MOUSE_SPEED_BASE;
    g_mouse.vy = (d > 0) ? (dy / d) * MOUSE_SPEED_BASE : 0.0f;
    g_mouse.facing         = (g_mouse.vx >= 0) ? 1 : -1;
    g_mouse.active         = true;
    g_mouse.dirChangeTicks = (uint8_t)catRand(5, 10);
    g_mouse.frame          = 0;
    g_mouse.tailPhase      = 0;
}

// Advance mouse: always running, zigzags randomly, panics when cat is near
static void mouseTick() {
    if (!g_mouse.active) return;

    g_mouse.frame++;
    g_mouse.tailPhase = (g_mouse.tailPhase + 1) & 7;

    float cdx     = g_mouse.x - g_cat.x;
    float cdy     = g_mouse.y - g_cat.y;
    float catDist = sqrtf(cdx * cdx + cdy * cdy);
    bool  panic   = (catDist < PANIC_DIST);
    float speed   = panic ? MOUSE_SPEED_PANIC : MOUSE_SPEED_BASE;

    // Direction changes: more frequent when panicking
    if (g_mouse.dirChangeTicks > 0) {
        g_mouse.dirChangeTicks--;
    } else {
        g_mouse.dirChangeTicks = panic ? (uint8_t)catRand(2, 6) : (uint8_t)catRand(5, 10);
        // Mostly flee from cat, deflected by a random angle
        float deflect = ((float)catRand(-55, 55)) * (3.14159f / 180.0f);
        float angle   = (catDist > 1.0f)
            ? atan2f(cdy, cdx) + deflect
            : (float)catRand(0, 628) / 100.0f;
        g_mouse.vx = cosf(angle) * speed;
        g_mouse.vy = sinf(angle) * speed;
    }

    // Blend velocity toward current speed magnitude (smooths speed transitions)
    float vMag = sqrtf(g_mouse.vx * g_mouse.vx + g_mouse.vy * g_mouse.vy);
    if (vMag > 0.01f) {
        g_mouse.vx = g_mouse.vx / vMag * speed;
        g_mouse.vy = g_mouse.vy / vMag * speed;
    }

    g_mouse.x += g_mouse.vx;
    g_mouse.y += g_mouse.vy;

    // Bounce off arena walls — reflect and re-randomize direction slightly
    if (g_mouse.x < ARENA_X0) { g_mouse.x = (float)ARENA_X0; g_mouse.vx =  fabsf(g_mouse.vx); g_mouse.dirChangeTicks = 1; }
    if (g_mouse.x > ARENA_X1) { g_mouse.x = (float)ARENA_X1; g_mouse.vx = -fabsf(g_mouse.vx); g_mouse.dirChangeTicks = 1; }
    if (g_mouse.y < ARENA_Y0) { g_mouse.y = (float)ARENA_Y0; g_mouse.vy =  fabsf(g_mouse.vy); g_mouse.dirChangeTicks = 1; }
    if (g_mouse.y > ARENA_Y1) { g_mouse.y = (float)ARENA_Y1; g_mouse.vy = -fabsf(g_mouse.vy); g_mouse.dirChangeTicks = 1; }

    g_mouse.facing = (g_mouse.vx >= 0) ? 1 : -1;
}

// ── Cat helpers ────────────────────────────────────────────────────────────

static void catPickNewBehavior() {
    int r = catRand(0, 99);
    if (r < 40) {
        g_cat.behavior = CatBehavior::WALK;
        g_cat.tx = (float)catRand(ARENA_X0, ARENA_X1);
        g_cat.ty = (float)catRand(ARENA_Y0, ARENA_Y1);
        g_cat.behaviorTicks = catRand(20, 50);
    } else if (r < 60) {
        g_cat.behavior = CatBehavior::SIT;
        g_cat.behaviorTicks = catRand(15, 40);
    } else if (r < 80) {
        g_cat.behavior = CatBehavior::LOOK_UP;
        g_cat.behaviorTicks = catRand(10, 25);
    } else {
        g_cat.behavior = CatBehavior::PAW_UP;
        g_cat.behaviorTicks = catRand(8, 20);
    }
}

static void catTick(uint32_t now) {
    if (!g_catInited) {
        g_catInited   = true;
        g_cat.lastMs  = now;
        // First mouse spawn: 5–12 seconds from init
        g_mouse.spawnCountdown = catRand(62, 150);
        catPickNewBehavior();
    }
    if (now - g_cat.lastMs < 80) return;
    g_cat.lastMs = now;

    g_cat.frame++;
    g_cat.tailPhase = (g_cat.tailPhase + 1) & 7;

    // ── Mouse spawn timer ──────────────────────────────────────────────────
    if (!g_mouse.active) {
        if (g_mouse.spawnCountdown > 0) {
            g_mouse.spawnCountdown--;
        } else {
            mouseSpawn();
        }
    }

    // ── Mouse movement ─────────────────────────────────────────────────────
    mouseTick();

    // ── Victory pose hold after a catch ───────────────────────────────────
    if (g_cat.victoryTicks > 0) {
        g_cat.victoryTicks--;
        g_cat.behavior = CatBehavior::PAW_UP;
        if (g_cat.victoryTicks == 0) catPickNewBehavior();
        return;
    }

    // ── Chase mode: override normal behavior when mouse is active ─────────
    if (g_mouse.active) {
        g_cat.behavior = CatBehavior::CHASE;
        float dx = g_mouse.x - g_cat.x;
        float dy = g_mouse.y - g_cat.y;
        float dist = sqrtf(dx * dx + dy * dy);

        if (dist < 14.0f) {
            // Caught! Disappear the mouse and strike a victory pose
            g_mouse.active = false;
            // Next spawn: 10–20 seconds later
            g_mouse.spawnCountdown = catRand(125, 250);
            g_cat.behavior     = CatBehavior::PAW_UP;
            g_cat.victoryTicks = 12;  // ~1 second
        } else {
            g_cat.x += (dx / dist) * CAT_CHASE_SPEED;
            g_cat.y += (dy / dist) * CAT_CHASE_SPEED;
            g_cat.facing = (dx >= 0) ? 1 : -1;
        }
        return;
    }

    // ── Normal wandering behavior ──────────────────────────────────────────
    if (g_cat.behaviorTicks > 0) g_cat.behaviorTicks--;
    if (g_cat.behaviorTicks == 0) catPickNewBehavior();

    if (g_cat.behavior == CatBehavior::WALK) {
        float dx = g_cat.tx - g_cat.x;
        float dy = g_cat.ty - g_cat.y;
        float dist = sqrtf(dx * dx + dy * dy);
        if (dist < 2.0f) {
            g_cat.behavior = CatBehavior::SIT;
            g_cat.behaviorTicks = catRand(15, 35);
        } else {
            g_cat.x += (dx / dist) * CAT_WALK_SPEED;
            g_cat.y += (dy / dist) * CAT_WALK_SPEED;
            g_cat.facing = (dx >= 0) ? 1 : -1;
        }
    }
}

// ── Draw helpers ───────────────────────────────────────────────────────────

static void catDraw(LGFX_Sprite& s, uint16_t bgCol) {
    const uint16_t col    = g_faceEyeBody565;
    const uint16_t earIn  = blendRGB565(col, bgCol, 110);   // inner ear
    const uint16_t wCol   = blendRGB565(col, bgCol, 50);    // whisker
    const bool chasing    = (g_cat.behavior == CatBehavior::CHASE);
    const bool victory    = (g_cat.behavior == CatBehavior::PAW_UP && g_cat.victoryTicks > 0);
    const int  fx         = g_cat.facing;
    const int  cx         = (int)g_cat.x;
    const int  cy         = (int)g_cat.y;

    // ── Tail ────────────────────────────────────────────────────────────────
    // Chase: streams straight back, raised. Idle: lazy S-curve sway.
    if (chasing) {
        // Tail whips straight back and up when sprinting
        int tx0 = cx - fx * 11, ty0 = cy;
        int tx1 = tx0 - fx * 7,  ty1 = ty0 - 5;
        int tx2 = tx1 - fx * 4,  ty2 = ty1 - 3;
        s.drawLine(tx0, ty0, tx1, ty1, col);
        s.drawLine(tx0 + 1, ty0, tx1 + 1, ty1, col);   // double-pixel for thickness
        s.drawLine(tx1, ty1, tx2, ty2, col);
        s.fillCircle(tx2, ty2, 2, col);
    } else {
        float tp  = (float)g_cat.tailPhase / 8.0f * 3.14159f * 2.0f;
        float swX = sinf(tp) * 6.0f;
        float swY = cosf(tp) * 4.0f;
        int tx0 = cx - fx * 10, ty0 = cy + 3;
        int tx1 = tx0 - fx * 6 + (int)swX, ty1 = ty0 - 7 + (int)swY;
        int tx2 = tx1 - fx * 4 + (int)(swX * 0.4f), ty2 = ty1 - 5;
        s.drawLine(tx0, ty0, tx1, ty1, col);
        s.drawLine(tx0, ty0 + 1, tx1, ty1 + 1, col);   // double-pixel
        s.drawLine(tx1, ty1, tx2, ty2, col);
        s.fillCircle(tx2, ty2, 2, col);
    }

    // ── Body ────────────────────────────────────────────────────────────────
    // Chase: stretched low (sprint silhouette). Normal: rounder.
    if (chasing) {
        s.fillEllipse(cx, cy + 1, 14, 6, col);   // low, elongated
    } else {
        s.fillEllipse(cx, cy, 12, 9, col);
    }

    // ── Head position depends on pose ───────────────────────────────────────
    int hx, hy;
    if (chasing) {
        hx = cx + fx * 13; hy = cy - 3;   // forward and low — pounce lean
    } else {
        hx = cx + fx * 10; hy = cy - 7;   // upright
    }
    s.fillCircle(hx, hy, 8, col);

    // ── Ears ────────────────────────────────────────────────────────────────
    // Near ear (facing side) — tall pointed triangle
    int nearEarX = hx + fx * 4;
    int farEarX  = hx - fx * 3;
    s.fillTriangle(nearEarX,        hy - 10,
                   nearEarX - fx*4, hy - 2,
                   nearEarX + fx*2, hy - 2, col);
    s.fillTriangle(farEarX,         hy - 9,
                   farEarX  - fx*3, hy - 2,
                   farEarX  + fx*3, hy - 2, col);
    // Inner ear
    s.fillTriangle(nearEarX,        hy - 8,
                   nearEarX - fx*2, hy - 3,
                   nearEarX + fx*1, hy - 3, earIn);

    // ── Eyes ────────────────────────────────────────────────────────────────
    bool lookUp   = (g_cat.behavior == CatBehavior::LOOK_UP);
    bool blinkNow = (!chasing && (g_cat.frame & 0x1F) == 0);
    int  neX      = hx + fx * 3;
    int  feX      = hx - fx * 2;
    int  eyY      = hy - 1;
    if (blinkNow) {
        // Thin closed line
        s.drawLine(neX - 3, eyY, neX + 3, eyY, bgCol);
        s.drawLine(feX - 3, eyY, feX + 3, eyY, bgCol);
    } else if (chasing) {
        // Wide alert pupils — large circles
        s.fillCircle(neX, eyY, 3, bgCol);
        s.fillCircle(feX, eyY, 3, bgCol);
        // Tiny highlight dot
        s.fillCircle(neX + 1, eyY - 1, 1, col);
        s.fillCircle(feX + 1, eyY - 1, 1, col);
    } else if (lookUp) {
        s.fillCircle(neX, eyY - 2, 2, bgCol);
        s.fillCircle(feX, eyY - 2, 2, bgCol);
    } else if (victory) {
        // Crescent happy squint — small filled ellipses
        s.fillEllipse(neX, eyY, 3, 2, bgCol);
        s.fillEllipse(feX, eyY, 3, 2, bgCol);
    } else {
        s.fillCircle(neX, eyY, 2, bgCol);
        s.fillCircle(feX, eyY, 2, bgCol);
    }

    // ── Legs ────────────────────────────────────────────────────────────────
    // Chase uses a gallop: legs splay further and alternate in bigger arcs
    {
        bool moving   = (chasing || g_cat.behavior == CatBehavior::WALK);
        // Chase animates every frame; walk every 2 frames
        int  legPhase = !moving ? 0 : chasing ? (g_cat.frame & 3) : ((g_cat.frame >> 1) & 3);

        int legRootY = cy + (chasing ? 5 : 8);

        // Front pair
        int f1x = cx + fx * 6;
        int f2x = cx + fx * 3;
        int f1ext = (legPhase == 0) ? 5 : (legPhase == 1) ? 3 : 1;
        int f2ext = (legPhase == 2) ? 5 : (legPhase == 3) ? 3 : 1;
        s.drawLine(f1x, legRootY, f1x + fx * (chasing ? 2 : 0), legRootY + 4 + f1ext, col);
        s.fillCircle(f1x + fx * (chasing ? 2 : 0), legRootY + 4 + f1ext, 2, col);
        s.drawLine(f2x, legRootY, f2x - fx * (chasing ? 2 : 0), legRootY + 4 + f2ext, col);
        s.fillCircle(f2x - fx * (chasing ? 2 : 0), legRootY + 4 + f2ext, 2, col);

        // Hind pair
        int h1x = cx - fx * 4;
        int h2x = cx - fx * 7;
        int h1ext = (legPhase == 2) ? 5 : (legPhase == 3) ? 3 : 1;
        int h2ext = (legPhase == 0) ? 5 : (legPhase == 1) ? 3 : 1;
        s.drawLine(h1x, legRootY, h1x - fx * (chasing ? 2 : 0), legRootY + 4 + h1ext, col);
        s.fillCircle(h1x - fx * (chasing ? 2 : 0), legRootY + 4 + h1ext, 2, col);
        s.drawLine(h2x, legRootY, h2x + fx * (chasing ? 2 : 0), legRootY + 4 + h2ext, col);
        s.fillCircle(h2x + fx * (chasing ? 2 : 0), legRootY + 4 + h2ext, 2, col);
    }

    // ── Raised front paw — victory pose ────────────────────────────────────
    if (g_cat.behavior == CatBehavior::PAW_UP) {
        int pawX = hx + fx * 6;
        int pawY = hy + 1;
        int bob  = ((g_cat.frame >> 2) & 1) ? -2 : 0;
        s.drawLine(pawX, pawY, pawX + fx * 1, pawY - 6 + bob, col);
        s.drawLine(pawX + 1, pawY, pawX + fx * 1 + 1, pawY - 6 + bob, col);
        s.fillCircle(pawX + fx * 1, pawY - 6 + bob, 3, col);
    }

    // ── Whiskers — 3 per side ───────────────────────────────────────────────
    int snoutX = hx + fx * 5;
    int snoutY = hy + 1;
    s.drawLine(snoutX,        snoutY - 2, snoutX + fx * 7, snoutY - 3, wCol);
    s.drawLine(snoutX,        snoutY,     snoutX + fx * 7, snoutY,     wCol);
    s.drawLine(snoutX,        snoutY + 2, snoutX + fx * 7, snoutY + 3, wCol);
    s.drawLine(snoutX - fx*2, snoutY - 2, snoutX - fx * 8, snoutY - 3, wCol);
    s.drawLine(snoutX - fx*2, snoutY,     snoutX - fx * 8, snoutY,     wCol);
    s.drawLine(snoutX - fx*2, snoutY + 2, snoutX - fx * 8, snoutY + 3, wCol);
}

static void mouseDraw(LGFX_Sprite& s, uint16_t bgCol) {
    if (!g_mouse.active) return;

    // Mouse is visually distinct — slightly dimmer/smaller than cat
    const uint16_t col   = blendRGB565(g_faceEyeBody565, bgCol, 175);
    const uint16_t earIn = blendRGB565(g_faceEyeBody565, bgCol, 65);
    const int  fx        = g_mouse.facing;
    const int  cx        = (int)g_mouse.x;
    const int  cy        = (int)g_mouse.y;

    // Speed magnitude — used to scale body stretch and tail behavior
    float spd = sqrtf(g_mouse.vx * g_mouse.vx + g_mouse.vy * g_mouse.vy);
    bool  fast = (spd > 4.5f);

    // ── Tail — streams flat behind when running fast, sways when slower ────
    {
        int tx0 = cx - fx * 5, ty0 = cy + 1;
        if (fast) {
            // Straight tail pointing back, slight upward angle
            s.drawLine(tx0, ty0, tx0 - fx * 8, ty0 - 2, col);
            s.drawLine(tx0 - fx * 8, ty0 - 2, tx0 - fx * 11, ty0 - 4, col);
        } else {
            float tp  = (float)g_mouse.tailPhase / 8.0f * 3.14159f * 2.0f;
            float swX = sinf(tp) * 3.0f;
            s.drawLine(tx0, ty0, tx0 - fx * 7 + (int)swX, ty0 + 3, col);
            s.drawLine(tx0 - fx * 7 + (int)swX, ty0 + 3, tx0 - fx * 9, ty0 + 5, col);
        }
    }

    // ── Body — slightly stretched horizontally when running fast ───────────
    int bodyW = fast ? 9 : 7;
    int bodyH = fast ? 4 : 5;
    s.fillEllipse(cx, cy, bodyW, bodyH, col);

    // ── Head ─────────────────────────────────────────────────────────────────
    int hx = cx + fx * 6, hy = cy - 3;
    s.fillCircle(hx, hy, 5, col);

    // ── Big round ears (mouse trademark) ────────────────────────────────────
    s.fillCircle(hx + fx * 2, hy - 5, 3, col);
    s.fillCircle(hx - fx * 2, hy - 5, 3, col);
    s.fillCircle(hx + fx * 2, hy - 5, 2, earIn);
    s.fillCircle(hx - fx * 2, hy - 5, 2, earIn);

    // ── Eye — tiny bright dot ────────────────────────────────────────────────
    s.fillCircle(hx + fx * 2, hy - 1, 1, bgCol);

    // ── Nose ─────────────────────────────────────────────────────────────────
    s.fillCircle(hx + fx * 4, hy + 1, 1, earIn);

    // ── Running legs — fast cycle animates every frame ───────────────────────
    {
        int  legPhase = g_mouse.frame & 3;
        int  legY     = cy + bodyH;
        // Front pair
        int f1x = cx + fx * 3;
        int f2x = cx + fx * 1;
        int f1e = (legPhase == 0 || legPhase == 1) ? 3 : 1;
        int f2e = (legPhase == 2 || legPhase == 3) ? 3 : 1;
        s.drawLine(f1x, legY, f1x + fx,  legY + f1e, col);
        s.drawLine(f2x, legY, f2x - fx,  legY + f2e, col);
        // Hind pair
        int h1x = cx - fx * 2;
        int h2x = cx - fx * 4;
        int h1e = (legPhase == 2 || legPhase == 3) ? 3 : 1;
        int h2e = (legPhase == 0 || legPhase == 1) ? 3 : 1;
        s.drawLine(h1x, legY, h1x - fx,  legY + h1e, col);
        s.drawLine(h2x, legY, h2x + fx,  legY + h2e, col);
    }
}

struct Palette {
    uint16_t bg, iris, irisRing, accent, mouth, label, sclera;
};

static const int EXPR_COUNT = (int)face::Expression::COUNT;

static const Palette PAL[EXPR_COUNT] = {
    //             bg              iris              irisRing          accent            mouth             label             sclera
    /* IDLE */    { rgb(0,0,0),    rgb(0,200,220),   rgb(0,140,160),   rgb(0,255,255),   rgb(150,155,175), rgb(180,180,190), rgb(245,245,250) },
    /* LISTEN */  { rgb(0,0,0),    rgb(0,230,100),   rgb(0,160,70),    rgb(0,255,120),   rgb(190,230,200), rgb(0,220,100),   rgb(245,245,250) },
    /* THINK */   { rgb(0,0,0),    rgb(100,200,255), rgb(60,150,220),  rgb(130,220,255), rgb(180,210,240), rgb(120,210,255), rgb(245,245,250) },
    /* SPEAK */   { rgb(0,0,0),    rgb(0,230,180),   rgb(0,180,130),   rgb(0,255,200),   rgb(220,240,235), rgb(0,240,180),   rgb(245,245,250) },
    /* CONFUS */  { rgb(0,0,0),    rgb(255,160,40),  rgb(200,110,20),  rgb(255,180,60),  rgb(230,195,140), rgb(255,170,40),  rgb(245,245,250) },
    /* SLEEP */   { rgb(0,0,0),    rgb(80,80,150),   rgb(50,50,110),   rgb(60,60,120),   rgb(110,110,170), rgb(90,90,140),   rgb(200,200,220) },
    /* OFFLN */   { rgb(0,0,0),    rgb(255,50,50),   rgb(190,30,30),   rgb(255,60,60),   rgb(170,90,90),   rgb(255,60,60),   rgb(245,245,250) },
    /* ENCOU */   { rgb(0,0,0),    rgb(255,210,60),  rgb(200,160,30),  rgb(255,220,80),  rgb(235,215,145), rgb(255,220,60),  rgb(245,245,250) },
    /* CALM */    { rgb(0,0,0),    rgb(80,220,120),  rgb(50,170,80),   rgb(100,240,140), rgb(170,225,190), rgb(80,230,120),  rgb(245,245,250) },
    /* FOCUS */   { rgb(0,0,0),    rgb(120,200,255), rgb(80,160,220),  rgb(140,220,255), rgb(195,220,250), rgb(130,210,255), rgb(245,245,250) },
    /* HAPPY */   { rgb(0,0,0),    rgb(255,100,180), rgb(200,60,140),  rgb(255,120,200), rgb(250,195,215), rgb(255,110,190), rgb(245,245,250) },
    /* SAD */     { rgb(0,0,0),    rgb(100,120,180), rgb(70,85,140),   rgb(80,100,160),  rgb(135,145,175), rgb(110,130,190), rgb(245,245,250) },
    /* SHRUG */   { rgb(0,0,0),    rgb(180,180,200), rgb(130,130,160), rgb(200,200,220), rgb(170,170,190), rgb(190,190,210), rgb(240,240,245) },
    /* SURPR */   { rgb(0,0,0),    rgb(255,210,60),  rgb(200,165,20),  rgb(255,230,100), rgb(250,220,160), rgb(255,225,80),  rgb(245,245,250) },
    /* SHOCK */   { rgb(0,0,0),    rgb(200,230,255), rgb(140,185,230), rgb(220,240,255), rgb(240,245,255), rgb(210,235,255), rgb(250,252,255) },
    /* ANGRY */   { rgb(0,0,0),    rgb(255,60,40),   rgb(200,30,20),   rgb(255,80,60),   rgb(180,80,70),   rgb(255,70,50),   rgb(245,200,200) },
    /* DISTR */   { rgb(0,0,0),    rgb(160,255,80),  rgb(110,200,40),  rgb(180,255,100), rgb(170,220,130), rgb(170,240,90),  rgb(240,250,230) },
};

struct EyeShape {
    int16_t r, pupilR, pupilOX, pupilOY;
    bool canBlink, hasBrows;
};

static const EyeShape EYES[EXPR_COUNT] = {
    /* IDLE */    { 42, 12,   0,   2, true,  false },
    /* LISTEN */  { 46, 13,   0,   0, false, false },
    /* THINK */   { 40, 12,   0,   0, true,  false },
    /* SPEAK */   { 42, 12,   0,   4, true,  false },
    /* CONFUS */  { 40, 13,  12,  -5, false, false },
    /* SLEEP */   {  0,  0,   0,   0, false, false },
    /* OFFLN */   { 36, 12,   0,   5, false, false },
    /* ENCOU */   { 44, 11,   0,  -8, true,  true  },
    /* CALM */    { 40, 14,   0,   0, true,  false },
    /* FOCUS */   { 38, 11,   0,   5, true,  false },
    /* HAPPY */   { 44, 11,   0,  -6, true,  true  },
    /* SAD */     { 38, 13,   0,  10, false, false },
    /* SHRUG */   { 40, 12,   0,   0, true,  true  },
    /* SURPR */   { 48, 10,   0,  -4, true,  true  },  // very wide, small pupils up, raised brows
    /* SHOCK */   { 50,  7,   0,   0, false, false },  // max wide, tiny pupils, no blink
    /* ANGRY */   { 32, 12,   0,   4, false, true  },  // narrow squint, brows on, no blink
    /* DISTR */   { 40, 12,   6,  -2, true,  false },  // offset pupils (asymmetric handled in tick)
};

// ── Display hardware implementation ───────────────────

namespace display_hw {

// Forward declaration — defined below, used by renderFace
void renderTranscriptOverlay(LGFX_Sprite& target, const char* text);

void init() {
    tft.init();
    tft.setRotation(0);        // Portrait: 240 wide x 320 tall
    tft.invertDisplay(true);   // ILI9341V — panel requires inversion for correct colors
    tft.fillScreen(COL_BG);
    tft.setBrightness(255);

    COL_DIM = tft.color565(80, 80, 80);
    COL_STATUS_BG = tft.color565(20, 20, 30);

    // Use pre-allocated PSRAM buffer for sprite (allocated before WiFi in main.cpp)
    sprite.setColorDepth(16);
    if (preallocSpriteBuffer) {
        // Clear the raw buffer first (PSRAM may contain garbage/0xFF = white)
        memset(preallocSpriteBuffer, 0, LCD_WIDTH * LCD_HEIGHT * 2);
        sprite.setBuffer(preallocSpriteBuffer, LCD_WIDTH, LCD_HEIGHT, 16);
        sprite.fillSprite(TFT_BLACK);  // ensure sprite starts black
        Serial.printf("[Display HW] Sprite buffer: %dx%d (%.1fKB, pre-allocated PSRAM)\n",
            LCD_WIDTH, LCD_HEIGHT, (LCD_WIDTH * LCD_HEIGHT * 2) / 1024.0f);
    } else {
        // Fallback: try allocating now (may fail if WiFi took PSRAM)
        sprite.setPsram(true);
        if (sprite.createSprite(LCD_WIDTH, LCD_HEIGHT) == nullptr) {
            Serial.println("[Display HW] WARNING: Sprite alloc failed — DIRECT DRAW WILL FLICKER");
        } else {
            Serial.printf("[Display HW] Sprite buffer: %dx%d (%.1fKB, late alloc)\n",
                LCD_WIDTH, LCD_HEIGHT, (LCD_WIDTH * LCD_HEIGHT * 2) / 1024.0f);
        }
    }

    tft.fillScreen(COL_BG);
    Serial.println("[Display HW] ILI9341 initialized (240x320)");
}

void clear() {
    tft.fillScreen(COL_BG);
}

void setBacklight(uint8_t level) {
    // LovyanGFX handles PWM backlight via the Light driver
    if (level == 0) {
        tft.setBrightness(0);
    } else {
        // Map 1-100 range to 30-255 (avoid too-dim levels)
        uint8_t pwm = map(level, 1, 100, 30, 255);
        tft.setBrightness(pwm);
    }
}

// ── Bezier rendering helpers ─────────────────────────

static void bezierPt(float t, float x0, float y0, float x1, float y1,
                     float x2, float y2, float& ox, float& oy) {
    float mt = 1.0f - t;
    ox = mt * mt * x0 + 2 * mt * t * x1 + t * t * x2;
    oy = mt * mt * y0 + 2 * mt * t * y1 + t * t * y2;
}

static void thickBezier(LGFX_Sprite& s, float x0, float y0, float x1, float y1,
                        float x2, float y2, int radius, uint16_t color, int steps = 24) {
    for (int i = 0; i <= steps; i++) {
        float t = (float)i / steps;
        float px, py;
        bezierPt(t, x0, y0, x1, y1, x2, y2, px, py);
        s.fillSmoothCircle((int32_t)px, (int32_t)py, radius, color);
    }
}

static void drawGlow(LGFX_Sprite& s, int x, int y, int maxR, uint16_t color, uint16_t bg, uint8_t peakAlpha = 80) {
    for (int i = 0; i < 6; i++) {
        int r = maxR - i * (maxR / 6);
        if (r < 1) continue;
        uint8_t a = (peakAlpha / 6) * (i + 1);
        s.fillCircle(x, y, r, blendRGB565(color, bg, a));
    }
}

// ── Eye rendering ─────────────────────────────────────

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
    static const int CR     = 4;
    static const int MAX_DX = 10;
    static const int MAX_DY = 5;
    uint16_t EYE_COL = g_faceEyeBody565;  // runtime-overridable via setFaceColors()

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

    // Clamp tilt so no corner can exceed the half-height — prevents inverted bodyH
    int maxTilt = hhTop > 0 ? hhTop - 1 : 0;
    if (tl >  maxTilt) tl =  maxTilt;
    if (tl < -maxTilt) tl = -maxTilt;
    if (tr >  maxTilt) tr =  maxTilt;
    if (tr < -maxTilt) tr = -maxTilt;

    // Base top (flat, no tilt)
    int baseTop = ey - hhTop;
    // Actual per-corner tops — raised corner has smaller Y (higher on screen)
    int leftTopY  = baseTop - tl;
    int rightTopY = baseTop - tr;
    int botY      = ey + hhBot;

    // Body: the rect that covers the region below the LOWER of the two corners
    int bodyTopY = max(leftTopY, rightTopY);

    int actualCR = CR;
    int bodyH = botY - bodyTopY;
    if (bodyH <= 0) {
        // Degenerate: tilt exceeded eye height — draw a flat line and return
        s.fillRoundRect(ex - eyeW / 2, bodyTopY, eyeW, 1, 1, EYE_COL);
        return;
    }
    if (actualCR > hhBot)   actualCR = (hhBot   > 1) ? hhBot   - 1 : 1;
    if (actualCR > bodyH/2) actualCR = (bodyH/2 > 1) ? bodyH/2 - 1 : 1;

    s.fillRoundRect(ex - eyeW / 2, bodyTopY, eyeW, bodyH, actualCR, EYE_COL);
    // Square off the top edge — round only the bottom corners.
    // Without this, the body rect's rounded top corners create a visible seam
    // where the tilt wedge (full-width scanlines) meets the narrower first rows
    // of the rounded rect.
    if (actualCR > 1)
        s.fillRect(ex - eyeW / 2, bodyTopY, eyeW, actualCR, EYE_COL);

    // Wedge: fills the raised area above bodyTopY using horizontal scanlines.
    // Scanlines give a clean pixel-perfect slant with no diagonal aliasing.
    if (leftTopY < rightTopY) {
        // Left corner is higher — right edge of the wedge slopes down left→right
        int span = rightTopY - leftTopY;
        for (int y = leftTopY; y < rightTopY; y++) {
            int w = (y - leftTopY + 1) * eyeW / span;
            if (w < 1) w = 1;
            s.fillRect(ex - eyeW / 2, y, w, 1, EYE_COL);
        }
    } else if (rightTopY < leftTopY) {
        // Right corner is higher — left edge of the wedge slopes down right→left
        int span = leftTopY - rightTopY;
        for (int y = rightTopY; y < leftTopY; y++) {
            int w = (y - rightTopY + 1) * eyeW / span;
            if (w < 1) w = 1;
            s.fillRect(ex + eyeW / 2 - w + 1, y, w, 1, EYE_COL);
        }
    }
}

static void drawEyeOpen(LGFX_Sprite& s, int cx, int cy, const EyeShape& eye,
                         float scaleY, float pupilDX, float pupilDY) {
    int r = eye.r;
    int rh = (int)(r * scaleY);
    if (rh < 4) {
        thickBezier(s, cx - r, cy, cx, cy + 4, cx + r, cy, 2, g_faceEyeBody565, 16);
        return;
    }
    if (rh < r) s.fillEllipse(cx, cy, r, rh, g_faceEyeBody565);
    else        s.fillSmoothCircle(cx, cy, r, g_faceEyeBody565);

    int px = cx + eye.pupilOX + (int)pupilDX;
    int py = cy + eye.pupilOY + (int)pupilDY;
    int maxOff = r - eye.pupilR - 1;
    if (maxOff < 3) maxOff = 3;
    px = constrain(px, cx - maxOff, cx + maxOff);
    py = constrain(py, cy - maxOff, cy + maxOff);

    s.fillSmoothCircle(px, py, eye.pupilR, TFT_BLACK);
    s.fillCircle(px - 3, py - 3, 2, TFT_WHITE);  // highlight
}

static void drawEyeClosed(LGFX_Sprite& s, int cx, int cy, int r, bool curveUp) {
    float bend = curveUp ? -5.0f : 4.0f;
    thickBezier(s, cx - r, cy, cx, cy + bend, cx + r, cy, 2, g_faceEyeBody565, 20);
}

static void drawEyeX(LGFX_Sprite& s, int cx, int cy, int size, uint16_t color, int thickness = 2) {
    int hs = size / 2;
    for (int i = -thickness; i <= thickness; i++) {
        s.drawLine(cx - hs + i, cy - hs, cx + hs + i, cy + hs, color);
        s.drawLine(cx + hs + i, cy - hs, cx - hs + i, cy + hs, color);
    }
}

static void drawBrow(LGFX_Sprite& s, int cx, int cy, int r, uint16_t accent, bool raised) {
    int by = cy - r - 6;
    float bend = raised ? -7.0f : -3.0f;
    thickBezier(s, cx - 14, by, cx, by + bend, cx + 14, by, 2, accent, 16);
}

// ── Mouth rendering ───────────────────────────────────

static void drawMouth(LGFX_Sprite& s, face::Expression expr, const Palette& pal,
                      float amp, float bounceY, float breathPhase) {
    int my = MOUTH_Y + (int)bounceY;
    bool talking = amp > 0.02f;
    const bool nova = (g_faceStyle && g_faceStyle->id == face_style::StyleId::NOVA);

    // Scale amplitude for mouth opening (boosted for visibility)
    float a = amp * 4.0f;
    if (a > 1.0f) a = 1.0f;

    switch (expr) {
        case face::Expression::IDLE: {
            if (talking) {
                // Rect slot — grows in height with amplitude (same for both styles)
                int mw = 60;
                int mh = 6 + (int)(a * 40);
                int cr = (mh < 8) ? mh / 2 : 8;
                s.fillRoundRect(CX - mw / 2, my - mh / 2, mw, mh, cr, pal.mouth);
                if (mh > 12) {
                    s.fillRoundRect(CX - mw / 2 + 4, my - mh / 2 + 4,
                                    mw - 8, mh - 8, cr,
                                    blendRGB565(pal.accent, pal.bg, 20));
                }
            } else {
                if (nova) {
                    float breathOff = sinf(breathPhase * 2 * 3.14159f) * 1.5f;
                    thickBezier(s, CX - 26, my + (int)breathOff,
                                   CX,      my + 8 + (int)breathOff,
                                   CX + 26, my + (int)breathOff,
                                3, pal.mouth);
                } else {
                    float breathOff = sinf(breathPhase * 2 * 3.14159f) * 1.5f;
                    thickBezier(s, CX - 30, my, CX, my + 10 + breathOff, CX + 30, my, 3, pal.mouth);
                }
            }
            break;
        }
        case face::Expression::LISTENING: {
            if (nova) {
                // Small rectangular dot — clearly square, attentive pause
                s.fillRoundRect(CX - 9, my - 5, 18, 11, 2, pal.mouth);
            } else {
                s.fillEllipse(CX, my, 7, 9, pal.mouth);
                s.fillEllipse(CX, my, 4, 6, blendRGB565(pal.accent, pal.bg, 40));
            }
            break;
        }
        case face::Expression::THINKING: {
            // Pursed lip shifted side-to-side — "hmm" look
            float thinkT = breathPhase * 6.28318f;
            int mxOff = (int)(sinf(thinkT * 1.2f) * 9.0f);
            if (nova) {
                // Nova: clean flat rectangle — matches rectangular style, no blurry inner
                int mw = 24;
                int mh = 5;
                s.fillRect(CX + mxOff - mw / 2, my - mh / 2, mw, mh, pal.mouth);
            } else {
                // Orbit: plain solid ellipse — no blurry inner highlight
                int mw = 10;
                int mh = 6;
                s.fillEllipse(CX + mxOff, my, mw, mh, pal.mouth);
            }
            break;
        }
        case face::Expression::SPEAKING: {
            // Wide rect slot — more dramatic range than idle (same for both styles)
            int mw = 68;
            int mh = 8 + (int)(a * 46);
            int cr = (mh < 8) ? mh / 2 : 8;
            s.fillRoundRect(CX - mw / 2, my - mh / 2, mw, mh, cr, pal.mouth);
            if (mh > 14) {
                s.fillRoundRect(CX - mw / 2 + 4, my - mh / 2 + 4,
                                mw - 8, mh - 8, cr,
                                blendRGB565(pal.accent, pal.bg, 20));
            }
            break;
        }
        case face::Expression::HAPPY: {
            if (talking) {
                // Wide rect slot, shifted down 4px (same for both styles)
                int mw = 70;
                int mh = 8 + (int)(a * 42);
                int cr = (mh < 8) ? mh / 2 : 8;
                s.fillRoundRect(CX - mw / 2, my - mh / 2 + 4, mw, mh, cr, pal.mouth);
                if (mh > 14) {
                    s.fillRoundRect(CX - mw / 2 + 4, my - mh / 2 + 8,
                                    mw - 8, mh - 8, cr,
                                    blendRGB565(pal.accent, pal.bg, 20));
                }
            } else {
                if (nova) {
                    // Open grin: rectangular border + punched black void + teeth hint
                    s.fillRoundRect(CX - 32, my, 64, 22, 4, pal.mouth);
                    s.fillRect(CX - 32, my, 64, 4, pal.mouth);        // square off top edge
                    s.fillRect(CX - 24, my + 5, 48, 13, pal.bg);     // punch open void
                    s.fillRect(CX - 22, my + 5, 44, 3,               // teeth strip
                               blendRGB565(TFT_WHITE, pal.mouth, 210));
                } else {
                    thickBezier(s, CX - 26, my, CX, my + 16, CX + 26, my, 3, pal.mouth);
                    thickBezier(s, CX - 16, my + 2, CX, my + 10, CX + 16, my + 2, 2,
                                blendRGB565(TFT_WHITE, pal.mouth, 160), 16);
                }
            }
            break;
        }
        case face::Expression::SAD: {
            if (talking) {
                if (nova) {
                    int mw = 34 + (int)(a * 20);
                    int mh = 10 + (int)(a * 32);
                    int cr = (mh < 10) ? mh / 2 : 6;
                    s.fillRoundRect(CX - mw / 2, my - mh / 2 + 2, mw, mh, cr, pal.mouth);
                    if (mh > 14) {
                        s.fillRoundRect(CX - mw / 2 + 3, my - mh / 2 + 5,
                                        mw - 6, mh - 6, cr,
                                        blendRGB565(pal.accent, pal.bg, 20));
                    }
                } else {
                    int ow = 38 + (int)(a * 16);
                    int oh = 12 + (int)(a * 32);
                    s.fillEllipse(CX, my + 2, ow / 2, oh / 2, pal.mouth);
                    if (oh > 14) {
                        s.fillEllipse(CX, my + 3, ow / 2 - 4, oh / 2 - 4,
                                      blendRGB565(pal.accent, pal.bg, 20));
                    }
                }
            } else {
                if (nova) {
                    // Arc frown — control above endpoints = bows upward = frown
                    float trem = sinf(breathPhase * 6.28318f * 3) * 1.5f;
                    thickBezier(s, CX - 22, my + 6 + (int)trem,
                                   CX,      my - 4 + (int)trem,
                                   CX + 22, my + 6 + (int)trem,
                                3, pal.mouth);
                } else {
                    float trem = sinf(breathPhase * 6.28318f * 3) * 1.0f;
                    thickBezier(s, CX - 18, my + 4, CX, my - 6 + trem, CX + 18, my + 4, 2, pal.mouth);
                }
            }
            break;
        }
        case face::Expression::ENCOURAGING: {
            if (talking) {
                if (nova) {
                    int mw = 50 + (int)(a * 18);
                    int mh = 10 + (int)(a * 40);
                    int cr = (mh < 10) ? mh / 2 : 8;
                    s.fillRoundRect(CX - mw / 2, my - mh / 2, mw, mh, cr, pal.mouth);
                    if (mh > 16) {
                        s.fillRoundRect(CX - mw / 2 + 4, my - mh / 2 + 4,
                                        mw - 8, mh - 8, cr,
                                        blendRGB565(pal.accent, pal.bg, 20));
                    }
                } else {
                    int ow = 48 + (int)(a * 20);
                    int oh = 14 + (int)(a * 42);
                    s.fillEllipse(CX, my, ow / 2, oh / 2, pal.mouth);
                    if (oh > 16) {
                        s.fillEllipse(CX, my + 1, ow / 2 - 4, oh / 2 - 4,
                                      blendRGB565(pal.accent, pal.bg, 20));
                    }
                }
            } else {
                if (nova) {
                    // Medium arc smile
                    thickBezier(s, CX - 24, my,     CX, my + 14, CX + 24, my,     4, pal.mouth);
                    thickBezier(s, CX - 15, my + 2, CX, my +  9, CX + 15, my + 2, 2,
                                blendRGB565(TFT_WHITE, pal.mouth, 120), 14);
                } else {
                    thickBezier(s, CX - 24, my, CX, my + 14, CX + 24, my, 3, pal.mouth);
                    thickBezier(s, CX - 14, my + 2, CX, my + 9, CX + 14, my + 2, 2,
                                blendRGB565(TFT_WHITE, pal.mouth, 120), 14);
                }
            }
            break;
        }
        case face::Expression::CALM: {
            if (talking) {
                if (nova) {
                    int mw = 32 + (int)(a * 16);
                    int mh = 8 + (int)(a * 26);
                    int cr = (mh < 8) ? mh / 2 : 6;
                    s.fillRoundRect(CX - mw / 2, my - mh / 2 + 2, mw, mh, cr, pal.mouth);
                    if (mh > 12) {
                        s.fillRoundRect(CX - mw / 2 + 3, my - mh / 2 + 5,
                                        mw - 6, mh - 6, cr,
                                        blendRGB565(pal.accent, pal.bg, 25));
                    }
                } else {
                    int ow = 36 + (int)(a * 14);
                    int oh = 10 + (int)(a * 28);
                    s.fillEllipse(CX, my + 2, ow / 2, oh / 2, pal.mouth);
                    if (oh > 12) {
                        s.fillEllipse(CX, my + 3, ow / 2 - 3, oh / 2 - 3,
                                      blendRGB565(pal.accent, pal.bg, 25));
                    }
                }
            } else {
                if (nova) {
                    // Medium short rect — relaxed neutral
                    int mw = 38, mh = 6;
                    s.fillRoundRect(CX - mw / 2, my + 1, mw, mh, mh / 2, pal.mouth);
                } else {
                    thickBezier(s, CX - 22, my + 2, CX, my + 5, CX + 22, my + 2, 3, pal.mouth);
                }
            }
            break;
        }
        case face::Expression::CONFUSED: {
            if (talking) {
                float wobble = sinf(breathPhase * 6.28f * 2) * 3.0f;
                if (nova) {
                    int mw = 32 + (int)(a * 18);
                    int mh = 10 + (int)(a * 28);
                    int cr = (mh < 10) ? mh / 2 : 6;
                    s.fillRoundRect(CX + (int)wobble - mw / 2, my - mh / 2, mw, mh, cr, pal.mouth);
                    if (mh > 14) {
                        s.fillRoundRect(CX + (int)wobble - mw / 2 + 3, my - mh / 2 + 3,
                                        mw - 6, mh - 6, cr,
                                        blendRGB565(pal.accent, pal.bg, 25));
                    }
                } else {
                    int ow = 36 + (int)(a * 18);
                    int oh = 12 + (int)(a * 30);
                    s.fillEllipse(CX + (int)wobble, my, ow / 2, oh / 2, pal.mouth);
                    if (oh > 14) {
                        s.fillEllipse(CX + (int)wobble, my + 1, ow / 2 - 4, oh / 2 - 4,
                                      blendRGB565(pal.accent, pal.bg, 25));
                    }
                }
            } else {
                if (nova) {
                    // Small rect with wobble offset — confused tic
                    float wobbleOff = sinf(breathPhase * 6.28f * 3.0f) * 3.0f;
                    int mw = 28, mh = 7;
                    s.fillRoundRect(CX - mw / 2 + (int)wobbleOff, my - mh / 2, mw, mh, mh / 2, pal.mouth);
                } else {
                    for (int i = 0; i <= 40; i++) {
                        float t = (float)i / 40;
                        int wx = CX - 20 + (int)(40 * t);
                        int wy = my + (int)(5.0f * sinf(t * 3.14159f * 3.0f + breathPhase * 6.28f));
                        s.fillCircle(wx, wy, 2, pal.mouth);
                    }
                }
            }
            break;
        }
        case face::Expression::FOCUSED: {
            if (talking) {
                if (nova) {
                    int mw = 28 + (int)(a * 12);
                    int mh = 8 + (int)(a * 22);
                    int cr = (mh < 8) ? mh / 2 : 5;
                    s.fillRoundRect(CX - mw / 2, my - mh / 2, mw, mh, cr, pal.mouth);
                    if (mh > 12) {
                        s.fillRoundRect(CX - mw / 2 + 3, my - mh / 2 + 3,
                                        mw - 6, mh - 6, cr,
                                        blendRGB565(pal.accent, pal.bg, 25));
                    }
                } else {
                    int ow = 32 + (int)(a * 12);
                    int oh = 10 + (int)(a * 24);
                    s.fillEllipse(CX, my, ow / 2, oh / 2, pal.mouth);
                    if (oh > 12) {
                        s.fillEllipse(CX, my + 1, ow / 2 - 3, oh / 2 - 3,
                                      blendRGB565(pal.accent, pal.bg, 25));
                    }
                }
            } else {
                if (nova) {
                    // Very narrow thin rect — tight focused line
                    int mw = 26, mh = 5;
                    s.fillRoundRect(CX - mw / 2, my - mh / 2, mw, mh, mh / 2, pal.mouth);
                } else {
                    thickBezier(s, CX - 16, my, CX - 5, my + 1, CX + 5, my + 1, 2, pal.mouth);
                    thickBezier(s, CX + 5, my + 1, CX + 16, my, CX + 16, my, 2, pal.mouth);
                }
            }
            break;
        }
        case face::Expression::SLEEPING: {
            // Three Zs at 120° phase offsets — each cycles from small+bright to large+faded
            // breathPhase drives the cycle; faster cycle (×1.5) so they feel lively
            for (int zi = 0; zi < 3; zi++) {
                float phase = fmodf(breathPhase * 1.5f + zi * 0.333f, 1.0f);
                int fontSize = 1 + (int)(phase * 2.0f);     // size 1→3
                int xPos = CX + 16 + (int)(phase * 18.0f);  // drifts right
                int yPos = my  -      (int)(phase * 42.0f);  // rises up
                // Fade quadratically so they're bright early and dim late
                uint8_t a = (uint8_t)(220.0f * (1.0f - phase * phase));
                s.setTextSize(fontSize);
                s.setTextColor(blendRGB565(pal.accent, pal.bg, a));
                s.drawChar('Z', xPos, yPos);
            }
            break;
        }
        case face::Expression::OFFLINE:
            if (nova) {
                // Thin flat rounded rect — straight dead line
                s.fillRoundRect(CX - 16, my - 3, 32, 6, 3, pal.mouth);
            } else {
                thickBezier(s, CX - 18, my, CX, my, CX + 18, my, 2, pal.mouth);
            }
            break;
        case face::Expression::SHRUG: {
            float bp = breathPhase * 2 * 3.14159f;
            if (nova) {
                // Small square rounded rect — pursed lips
                s.fillRoundRect(CX - 6, my - 6, 12, 12, 3, pal.mouth);
                s.fillRoundRect(CX - 3, my - 3, 6, 6, 2, blendRGB565(pal.accent, pal.bg, 40));
            } else {
                // Pursed mouth (small circle)
                s.fillSmoothCircle(CX, my, 5, pal.mouth);
                s.fillSmoothCircle(CX, my, 2, blendRGB565(pal.accent, pal.bg, 40));
            }
            // Floating bubble — grows and drifts right from mouth (same for both)
            float bubbleT = fmodf(breathPhase * 3.0f, 1.0f);  // 3x faster cycle
            int bubbleR = 3 + (int)(bubbleT * 8);
            int bubbleX = CX + 10 + (int)(bubbleT * 30);
            int bubbleY = my - (int)(bubbleT * 20);
            uint8_t bubbleAlpha = (uint8_t)(200 * (1.0f - bubbleT));
            uint16_t bubbleCol = blendRGB565(pal.accent, pal.bg, bubbleAlpha);
            s.drawCircle(bubbleX, bubbleY, bubbleR, bubbleCol);
            if (bubbleR > 4) {
                s.fillSmoothCircle(bubbleX - bubbleR/3, bubbleY - bubbleR/3, 2,
                                   blendRGB565(TFT_WHITE, pal.bg, bubbleAlpha));
            }
            break;
        }
        case face::Expression::SURPRISED: {
            // Wide open "O" mouth — "oh wow!"
            float pulse = sinf(breathPhase * 2 * 3.14159f) * 0.1f + 0.9f;
            if (nova) {
                // Rectangular open mouth — matches Nova's square language
                int mw = (int)(44 * pulse);
                int mh = (int)(52 * pulse);
                s.fillRoundRect(CX - mw / 2, my - mh / 2, mw, mh, 4, pal.mouth);
                // Square off the top edge
                s.fillRect(CX - mw / 2, my - mh / 2, mw, 4, pal.mouth);
                // Dark inner cavity
                s.fillRoundRect(CX - mw / 2 + 5, my - mh / 2 + 5, mw - 10, mh - 10, 3,
                                blendRGB565(pal.accent, pal.bg, 40));
            } else {
                int ow = (int)(26 * pulse);
                int oh = (int)(28 * pulse);
                s.fillEllipse(CX, my, ow, oh, pal.mouth);
                s.fillEllipse(CX, my + 1, ow - 5, oh - 5, blendRGB565(pal.accent, pal.bg, 25));
            }
            break;
        }
        case face::Expression::SHOCKED: {
            // Maximum gape — jaw dropped open, trembling slightly
            float trem = sinf(breathPhase * 6.28f * 5) * 1.5f;
            if (nova) {
                // Rectangular gape — sharp corners, trembling
                int mw = 52;
                int mh = 56 + (int)trem;
                s.fillRoundRect(CX - mw / 2, my - mh / 2 + 4, mw, mh, 4, pal.mouth);
                // Square off the top
                s.fillRect(CX - mw / 2, my - mh / 2 + 4, mw, 4, pal.mouth);
                // Dark inner cavity
                s.fillRoundRect(CX - mw / 2 + 5, my - mh / 2 + 9, mw - 10, mh - 10, 3,
                                blendRGB565(pal.accent, pal.bg, 40));
            } else {
                int ow = 32;
                int oh = 34 + (int)trem;
                s.fillEllipse(CX, my + 4, ow, oh, pal.mouth);
                s.fillEllipse(CX, my + 5, ow - 6, oh - 6, blendRGB565(pal.accent, pal.bg, 20));
            }
            break;
        }
        case face::Expression::ANGRY: {
            if (talking) {
                if (nova) {
                    int mw = 24 + (int)(a * 14);
                    int mh = 8 + (int)(a * 20);
                    int cr = (mh < 8) ? mh / 2 : 5;
                    s.fillRoundRect(CX - mw / 2, my - mh / 2, mw, mh, cr, pal.mouth);
                } else {
                    // Aggressive choppy talking mouth
                    int ow = 28 + (int)(a * 12);
                    int oh = 10 + (int)(a * 20);
                    s.fillEllipse(CX, my, ow / 2, oh / 2, pal.mouth);
                }
            } else {
                if (nova) {
                    // Rectangular clenched grimace — two thin rects with a gap (teeth)
                    // Upper lip bar
                    s.fillRect(CX - 22, my - 2, 44, 4, pal.mouth);
                    // Lower lip bar (slightly narrower, gap between = exposed teeth)
                    s.fillRect(CX - 18, my + 4, 36, 4, pal.mouth);
                    // Thin white teeth strip in the gap
                    s.fillRect(CX - 16, my + 2, 32, 2,
                               blendRGB565(TFT_WHITE, pal.mouth, 180));
                } else {
                    // Tight clenched frown
                    thickBezier(s, CX - 20, my + 2, CX, my - 6, CX + 20, my + 2, 3, pal.mouth);
                    thickBezier(s, CX - 12, my + 2, CX, my - 2, CX + 12, my + 2, 1,
                                blendRGB565(TFT_WHITE, pal.mouth, 100), 12);
                }
            }
            break;
        }
        case face::Expression::DISTURBED: {
            // Wobbly asymmetric mouth — unsettled
            float t = breathPhase * 2 * 3.14159f;
            float wobble = sinf(t * 2.3f) * 3.0f;
            float twist = sinf(t * 1.7f) * 4.0f;
            if (nova) {
                // Short rounded rect with wobble offsets
                int mw = 36, mh = 7;
                int xOff = (int)(wobble * 0.7f);
                int yOff = (int)(twist * 0.5f);
                s.fillRoundRect(CX - mw / 2 + xOff, my - mh / 2 + yOff, mw, mh, mh / 2, pal.mouth);
            } else {
                int lx = CX - 22, rx = CX + 22;
                int lOff = (int)(wobble + twist);
                int rOff = (int)(-wobble * 0.5f);
                thickBezier(s, lx, my + 4 + lOff, CX, my - 2, rx, my + 4 + rOff, 2, pal.mouth);
            }
            break;
        }
        default: break;
    }
}

// ── Main face renderer ────────────────────────────────

void renderFace(const face::FaceState& fs, const display::StatusBar& status) {
    LGFX_Sprite& s = sprite.getBuffer() ? sprite : (LGFX_Sprite&)tft;
    bool useSprite = (sprite.getBuffer() != nullptr);

    int exprIdx = (int)fs.expression;
    if (exprIdx < 0 || exprIdx >= EXPR_COUNT) exprIdx = 0;
    // Copy so we can apply runtime color overrides without modifying the const table.
    Palette pal = PAL[exprIdx];
    pal.bg = rgb((g_faceBgColor >> 16) & 0xFF,
                 (g_faceBgColor >>  8) & 0xFF,
                  g_faceBgColor        & 0xFF);
    pal.mouth = g_faceMouth565;
    const EyeShape& eye = EYES[exprIdx];

    // Clear with (overridable) background
    if (useSprite) s.fillSprite(pal.bg);
    else           tft.fillScreen(pal.bg);

    // Ambient glow — subtle for idle, stronger for active expressions
    if (fs.expression != face::Expression::IDLE) {
        float gp = sinf(fs.glowPhase) * 0.3f + 0.7f;
        drawGlow(s, CX, CY, 60, pal.accent, pal.bg, (uint8_t)(8 * gp));
    }

    // Apply popScale (disappear/reappear animation) + speaking nod
    float ps = fs.popScale;
    int eyeSpace = (int)(EYE_SPACE * ps);
    int faceOY = (int)((fs.bounceY + fs.speakingNodY) * ps);
    int leftEyeX  = CX - eyeSpace + (int)(fs.fidgetX * ps);
    int rightEyeX = CX + eyeSpace + (int)(fs.fidgetX * ps);
    int eyeY      = CY + faceOY + (int)(fs.fidgetY * ps);

    // Energy peak → draw brows on any expression while talking
    bool drawPeakBrows = fs.energyPeak && fs.mouthAmp > 0.02f;

    // Skip face rendering if fully popped away
    if (ps < 0.01f) goto skip_face;

    {
    // ── Eyes ─────────────────────────────────────────
    // Per-eye scale: combine blink with idle micro-animation scale
    float leftScale  = fs.blinkScale * fs.leftEyeScale * ps;
    float rightScale = fs.blinkScale * fs.rightEyeScale * ps;

    // Scaled eye shape for pop/curious effects
    EyeShape leftEye = eye;
    EyeShape rightEye = eye;
    leftEye.r = (int16_t)(eye.r * fs.leftEyeScale * ps);
    leftEye.pupilR = (int16_t)(eye.pupilR * fs.leftEyeScale * ps);
    rightEye.r = (int16_t)(eye.r * fs.rightEyeScale * ps);
    rightEye.pupilR = (int16_t)(eye.pupilR * fs.rightEyeScale * ps);

    // DISTURBED: asymmetric eye sizes — left eye wide, right eye squinting
    if (fs.expression == face::Expression::DISTURBED) {
        leftEye.r  = (int16_t)(leftEye.r  * 1.20f);
        leftEye.pupilR = (int16_t)(leftEye.pupilR * 1.10f);
        rightEye.r = (int16_t)(rightEye.r * 0.80f);
        rightEye.pupilR = (int16_t)(rightEye.pupilR * 0.85f);
    }

    if (fs.expression == face::Expression::SLEEPING) {
        const bool novaSleep = (g_faceStyle && g_faceStyle->id == face_style::StyleId::NOVA);
        float bOff = sinf(fs.breathPhase * 2 * 3.14159f) * 3.0f;
        if (novaSleep) {
            // Nova: thin flat rect slits — matches rectangular eye language
            int slitW = 68, slitH = 3;
            int slitY = eyeY - slitH / 2 + (int)bOff;
            s.fillRect(leftEyeX  - slitW / 2, slitY, slitW, slitH, g_faceEyeBody565);
            s.fillRect(rightEyeX - slitW / 2, slitY, slitW, slitH, g_faceEyeBody565);
        } else {
            drawEyeClosed(s, leftEyeX,  eyeY + (int)bOff, 24, false);
            drawEyeClosed(s, rightEyeX, eyeY + (int)bOff, 24, false);
        }
    } else if (fs.expression == face::Expression::OFFLINE) {
        const bool novaOff = (g_faceStyle && g_faceStyle->id == face_style::StyleId::NOVA);
        if (novaOff) {
            // Nova OFFLINE: same flat rounded-rect as idle, no squint, no drift.
            // The X is drawn on top — dead-screen look.
            drawEyeV2(s, leftEyeX,  eyeY, 1.0f, 0.0f, 0.0f, 0.0f, 68, 38);
            drawEyeV2(s, rightEyeX, eyeY, 1.0f, 0.0f, 0.0f, 0.0f, 68, 38);
            // Thick X — size 34 + thickness 4 for a bold dead-screen look
            drawEyeX(s, leftEyeX,  eyeY, 34, pal.accent, 4);
            drawEyeX(s, rightEyeX, eyeY, 34, pal.accent, 4);
        } else {
            // Orbit OFFLINE: plain white circle, NO pupil, X on top.
            s.fillSmoothCircle(leftEyeX,  eyeY, leftEye.r,  TFT_WHITE);
            s.fillSmoothCircle(rightEyeX, eyeY, rightEye.r, TFT_WHITE);
            drawEyeX(s, leftEyeX,  eyeY, 20, pal.accent);
            drawEyeX(s, rightEyeX, eyeY, 20, pal.accent);
        }
    } else {
        const face_style::ExprEyeStyle& es = g_faceStyle->eyes[exprIdx];

        if (es.useRoundRect) {
            // ── NOVA: data-driven rounded-rectangle eyes ─────────────────
            float squint = es.squintBase + fs.mouthAmp * es.squintAmpScale;
            if (es.squintMax > 0.0f && squint > es.squintMax) squint = es.squintMax;
            float dx = fs.driftX * es.driftDamp;
            float dy = fs.driftY * es.driftDamp;

            // DISTURBED: asymmetric eye sizes (wide left, squinted right)
            int lw = es.eyeW, lh = es.eyeH;
            int rw = es.eyeW, rh = es.eyeH;
            if (fs.expression == face::Expression::DISTURBED) {
                lw = (int)(lw * 1.20f); lh = (int)(lh * 1.20f);
                rw = (int)(rw * 0.80f); rh = (int)(rh * 0.80f);
            }
            drawEyeV2(s, leftEyeX,  eyeY, leftScale,  dx, dy, squint, lw, lh,
                       es.tiltOuter, es.tiltInner);
            drawEyeV2(s, rightEyeX, eyeY, rightScale, dx, dy, squint, rw, rh,
                       es.tiltInner, es.tiltOuter);

            // Nova reads emotion from eye tilt — no brows for any expression or peak event
            const bool isNova = (g_faceStyle && g_faceStyle->id == face_style::StyleId::NOVA);
            if (!isNova && (es.hasBrows || drawPeakBrows)) {
                int br = es.eyeH / 2;
                if (fs.expression == face::Expression::ANGRY) {
                    // V-shape angry brows
                    int lby = eyeY - br - 6;
                    int rby = eyeY - br - 6;
                    thickBezier(s, leftEyeX  - 14, lby - 6, leftEyeX  + 2, lby + 3, leftEyeX  + 14, lby + 8, 2, pal.accent, 16);
                    thickBezier(s, rightEyeX - 14, rby + 8, rightEyeX - 2, rby + 3, rightEyeX + 14, rby - 6, 2, pal.accent, 16);
                } else {
                    bool raised = (fs.expression == face::Expression::HAPPY ||
                                   fs.expression == face::Expression::SURPRISED) || drawPeakBrows;
                    drawBrow(s, leftEyeX,  eyeY, br, pal.accent, raised);
                    drawBrow(s, rightEyeX, eyeY, br, pal.accent, raised);
                }
            }
        } else {
            // ── ORBIT: classic circle eyes ────────────────────────────────
            if (leftScale < 0.05f) {
                bool curveUp = (fs.expression == face::Expression::HAPPY ||
                               fs.expression == face::Expression::ENCOURAGING);
                drawEyeClosed(s, leftEyeX, eyeY, leftEye.r, curveUp);
            } else {
                drawEyeOpen(s, leftEyeX, eyeY, leftEye, leftScale, fs.driftX, fs.driftY);
            }
            if (rightScale < 0.05f) {
                bool curveUp = (fs.expression == face::Expression::HAPPY ||
                               fs.expression == face::Expression::ENCOURAGING);
                drawEyeClosed(s, rightEyeX, eyeY, rightEye.r, curveUp);
            } else {
                drawEyeOpen(s, rightEyeX, eyeY, rightEye, rightScale, fs.driftX, fs.driftY);
            }
            if (es.hasBrows || drawPeakBrows) {
                if (fs.expression == face::Expression::ANGRY) {
                    int lby = eyeY - leftEye.r - 6;
                    int rby = eyeY - rightEye.r - 6;
                    thickBezier(s, leftEyeX  - 14, lby - 6, leftEyeX  + 2, lby + 3, leftEyeX  + 14, lby + 8, 2, pal.accent, 16);
                    thickBezier(s, rightEyeX - 14, rby + 8, rightEyeX - 2, rby + 3, rightEyeX + 14, rby - 6, 2, pal.accent, 16);
                } else {
                    bool raised = (fs.expression == face::Expression::HAPPY ||
                                   fs.expression == face::Expression::SURPRISED) || drawPeakBrows;
                    drawBrow(s, leftEyeX,  eyeY, leftEye.r, pal.accent, raised);
                    drawBrow(s, rightEyeX, eyeY, rightEye.r, pal.accent, raised);
                }
            }
        }
    }

    // ── Mouth ────────────────────────────────────────
    // Yawn overrides normal mouth when active
    if (fs.yawnAmp > 0.01f) {
        int my = MOUTH_Y + (int)(fs.bounceY * ps);
        uint16_t inside = blendRGB565(pal.accent, pal.bg, 30);
        if (g_faceStyle && g_faceStyle->id == face_style::StyleId::NOVA) {
            int mw = (int)(22 + fs.yawnAmp * 28);
            int mh = (int)(8 + fs.yawnAmp * 38);
            int cr = mw / 3;
            s.fillRoundRect(CX - mw / 2, my - mh / 2, mw, mh, cr, pal.mouth);
            if (mh > 10) s.fillRoundRect(CX - mw / 2 + 4, my - mh / 2 + 4, mw - 8, mh - 8, cr, inside);
        } else {
            int ow = (int)(12 + fs.yawnAmp * 14);
            int oh = (int)(4 + fs.yawnAmp * 20);
            s.fillEllipse(CX, my, ow, oh, pal.mouth);
            if (oh > 6) s.fillEllipse(CX, my, ow - 3, oh - 3, inside);
        }
    } else {
        drawMouth(s, fs.expression, pal, fs.mouthAmp, fs.bounceY * ps, fs.breathPhase);
    }
    }
    skip_face:

    // ── Thinking dots (bottom, bouncing) ─────────────────
    if (fs.expression == face::Expression::THINKING) {
        const bool novaThink = (g_faceStyle && g_faceStyle->id == face_style::StyleId::NOVA);
        int baseY = LCD_HEIGHT - 42;
        for (int i = 0; i < 3; i++) {
            int dx = CX - 18 + i * 18;
            bool lit = i < fs.thinkDots;
            // Bounce: active dot jumps up
            float bounce = lit ? sinf(fs.glowPhase * 4.0f + i * 0.8f) * 6.0f : 0.0f;
            int dy = baseY - (int)(bounce > 0.0f ? bounce : 0.0f);
            // Lit = full accent, unlit = clearly visible but muted (no glow bloat)
            uint16_t col = lit ? pal.accent : blendRGB565(pal.accent, pal.bg, 80);
            if (novaThink) {
                // Nova: crisp filled squares — matches rectangular eye style
                int sz = lit ? 7 : 5;
                s.fillRect(dx - sz / 2, dy - sz / 2, sz, sz, col);
            } else {
                // Orbit: solid circles — no drawGlow (it was the blur source)
                int r = lit ? 5 : 3;
                s.fillSmoothCircle(dx, dy, r, col);
            }
        }
    }

    // ── Listening pulse ──────────────────────────────
    if (fs.expression == face::Expression::LISTENING) {
        int ly = LCD_HEIGHT - 45;
        float pulse = sinf(fs.listenPhase) * 0.5f + 0.5f;
        int r = 6 + (int)(pulse * 5);
        drawGlow(s, CX, ly, r + 10, pal.accent, pal.bg, (uint8_t)(30 + pulse * 40));
        s.fillSmoothCircle(CX, ly, r, pal.accent);
    }

    // ── Sad teardrop ─────────────────────────────────
    if (fs.tearActive) {
        int tx = CX + fs.tearSide * EYE_SPACE;
        int ty = CY + (int)fs.tearY;
        uint16_t tearCol = blendRGB565(rgb(100, 150, 255), pal.bg, 180);
        s.fillSmoothCircle(tx, ty + 3, 3, tearCol);
        s.fillTriangle(tx - 2, ty + 2, tx + 2, ty + 2, tx, ty - 3, tearCol);
    }

    // ── Shocked "!!" — two exclamation marks shake above face ──
    if (fs.expression == face::Expression::SHOCKED) {
        float trem = sinf(fs.glowPhase * 8.0f) * 3.0f;  // rapid tremor
        float bobY  = sinf(fs.glowPhase * 1.2f) * 4.0f;
        int qy = eyeY - 72 + (int)bobY;
        s.setTextSize(5);
        s.setTextColor(pal.accent);
        s.setTextDatum(lgfx::middle_center);
        s.drawString("!", CX - 16 + (int)trem, qy);
        s.drawString("!", CX + 16 - (int)trem, qy);
        s.setTextDatum(lgfx::top_left);
    }

    // ── Confused question mark (floating above face) ──
    if (fs.expression == face::Expression::CONFUSED) {
        float t = fs.glowPhase * 1.5f;  // reuse glow phase for animation
        // Bob up and down
        float bobY = sinf(t) * 6.0f;
        // Gentle tilt via horizontal offset
        float tiltX = sinf(t * 0.7f) * 4.0f;
        // Pulse size
        float scale = 1.0f + sinf(t * 2.0f) * 0.1f;

        int qx = CX + 35 + (int)tiltX;  // offset right of center
        int qy = eyeY - 70 + (int)bobY;  // higher above the face

        // Draw "?" with scaled text
        int textSize = (int)(5 * scale);
        if (textSize < 4) textSize = 4;
        s.setTextSize(textSize);
        s.setTextColor(pal.accent);
        s.setTextDatum(lgfx::middle_center);
        s.drawString("?", qx, qy);
        s.setTextDatum(lgfx::top_left);
    }

    // ── Connection indicator (top-left dot) ────────────
    // Green = online, Yellow = WiFi only, Red = offline
    // Blinks orange when data flow stalls during speaking/thinking
    uint16_t dotCol;
    bool blinkDot = false;
    if (status.connectionStalled) {
        dotCol = rgb(255, 140, 0);  // orange — stalled
        blinkDot = true;
    } else if (status.wifiConnected && status.wsConnected) {
        dotCol = rgb(0, 200, 80);   // green — fully online
    } else if (status.wifiConnected) {
        dotCol = rgb(220, 180, 0);  // yellow — WiFi but no backend
    } else {
        dotCol = rgb(200, 50, 40);  // red — offline
    }
    // Blink: 500ms on / 500ms off
    if (!blinkDot || ((millis() / 500) % 2 == 0)) {
        s.fillSmoothCircle(8, 8, 4, dotCol);
    }

    // ── BLE presence indicator (next to connection dot) ──
    // Hidden when presence is disabled.
    // Solid bright blue  = phone detected (PRESENT / LEAVING).
    // Blinking medium blue = scanning, phone not yet seen (1000ms period,
    //   slower than the 500ms stall blink so the two are visually distinct).
    if (status.blePresenceEnabled) {
        if (status.blePresent) {
            // Solid bright blue — confirmed present
            s.fillSmoothCircle(20, 8, 4, rgb(60, 160, 255));
            s.fillSmoothCircle(24, 5, 1, rgb(60, 160, 255));
            s.fillSmoothCircle(24, 11, 1, rgb(60, 160, 255));
        } else {
            // Blink 1000ms on / 1000ms off — scanning, not yet detected
            if ((millis() / 1000) % 2 == 0) {
                s.fillSmoothCircle(20, 8, 4, rgb(50, 90, 200));
                s.fillSmoothCircle(24, 5, 1, rgb(50, 90, 200));
                s.fillSmoothCircle(24, 11, 1, rgb(50, 90, 200));
            }
            // Off half of the cycle — dot disappears, clearly "not found yet"
        }
    }

    // ── Status icon (bottom) — small icon instead of text label ──
    {
        int iconY = LCD_HEIGHT - 24;
        uint16_t iconCol = blendRGB565(pal.accent, pal.bg, 160);

        if (fs.expression == face::Expression::LISTENING) {
            // Mic icon — three vertical bars
            s.fillRoundRect(CX - 3, iconY - 8, 6, 12, 2, iconCol);
            s.drawRoundRect(CX - 8, iconY + 2, 16, 6, 2, iconCol);
            s.drawFastVLine(CX, iconY + 8, 4, iconCol);
        }
        else if (fs.expression == face::Expression::SPEAKING) {
            // Speaker icon — triangle + waves
            s.fillTriangle(CX - 6, iconY - 4, CX - 6, iconY + 4, CX + 2, iconY, iconCol);
            s.drawArc(CX + 4, iconY, 5, 4, 315, 45, iconCol);
            s.drawArc(CX + 4, iconY, 9, 8, 315, 45, iconCol);
        }
        else if (fs.expression == face::Expression::THINKING) {
            // Three animated dots already shown above — no extra icon needed
        }
    }

    // Draw transcript overlay into sprite (before push — avoids flicker)
    if (transcriptEnabled && transcriptText[0] != '\0') {
        renderTranscriptOverlay(s, transcriptText);
    }

    // BIOS overlay: header bar (top) + nav bar (bottom), baked in before push
    if (g_biosOverlay.enabled) {
        const uint16_t HDR = 0x0010;   // dark navy
        const uint16_t CYN = 0x07FF;   // cyan
        const uint16_t DIM = 0x8C71;   // grey
        const uint16_t DIM2 = 0x2104;  // dark grey

        // Header bar
        s.fillRect(0, 0, LCD_WIDTH, 26, HDR);
        s.drawFastHLine(0, 26, LCD_WIDTH, CYN);
        s.setFont(&fonts::FreeSans9pt7b);
        s.setTextSize(1);
        s.setTextColor(CYN);
        s.setTextDatum(lgfx::top_center);
        s.drawString(g_biosOverlay.title, LCD_WIDTH / 2, 6);
        s.setFont(&fonts::Font2);
        s.setTextColor(DIM);
        s.setTextDatum(lgfx::top_right);
        s.drawString(g_biosOverlay.counter, LCD_WIDTH - 6, 9);

        // Nav bar
        s.fillRect(0, 288, LCD_WIDTH, 32, HDR);
        s.drawFastHLine(0, 288, LCD_WIDTH, DIM2);
        s.setFont(&fonts::Font2);
        s.setTextSize(1);
        s.setTextColor(DIM2);
        s.setTextDatum(lgfx::top_left);
        s.drawString(g_biosOverlay.navL, 8, 295);
        s.setTextColor(DIM);
        s.setTextDatum(lgfx::top_center);
        s.drawString(g_biosOverlay.navC, LCD_WIDTH / 2, 295);
        s.setTextColor(DIM2);
        s.setTextDatum(lgfx::top_right);
        s.drawString(g_biosOverlay.navR, LCD_WIDTH - 8, 295);
    }

    if (useSprite) sprite.pushSprite(0, 0);
}

void renderClock(const display::StatusBar& status) {
    // Tick the cat every ~80ms regardless of minute change.
    uint32_t nowMs = millis();
    catTick(nowMs);

    // Redraw when minute changes, on first entry, or on each cat animation tick.
    static uint32_t lastClockMin    = 0xFFFFFFFFu;
    static uint32_t lastCatRedrawMs = 0;

    uint32_t elapsedMin = (syncedAtMs > 0) ? (nowMs - syncedAtMs) / 60000 : 0;
    uint32_t totalMin   = (syncedMinutes + elapsedMin) % (24 * 60);
    bool catDue = (nowMs - lastCatRedrawMs >= 80);
    if (totalMin == lastClockMin && !g_clockDirty && !catDue) return;
    lastClockMin = totalMin;
    g_clockDirty = false;
    if (catDue) lastCatRedrawMs = nowMs;

    LGFX_Sprite& s = sprite.getBuffer() ? sprite : (LGFX_Sprite&)tft;
    bool useSprite  = (sprite.getBuffer() != nullptr);

    // Background matches the face bg override
    uint16_t bgCol = rgb(
        (g_faceBgColor >> 16) & 0xFF,
        (g_faceBgColor >>  8) & 0xFF,
         g_faceBgColor        & 0xFF);

    if (useSprite) s.fillSprite(bgCol);
    else           tft.fillScreen(bgCol);

    s.setTextDatum(lgfx::middle_center);

    // Time — ticks locally from seeded sync point
    char timeBuf[8];
    if (syncedAtMs > 0) {
        uint8_t lh = (uint8_t)(totalMin / 60);
        uint8_t lm = (uint8_t)(totalMin % 60);
        snprintf(timeBuf, sizeof(timeBuf), "%02d:%02d", lh, lm);
    } else {
        strncpy(timeBuf, "--:--", sizeof(timeBuf));
    }

    // Time text — matches eye body color
    s.setFont(&fonts::Font0);
    s.setTextSize(6);
    s.setTextColor(g_faceEyeBody565);
    s.drawString(timeBuf, CX, CY - 20);

    // Date — dimmed version of the eye color
    s.setTextSize(2);
    s.setTextColor(blendRGB565(g_faceEyeBody565, bgCol, 100));
    const char* dateStr = (contextDataAvailable && latestContext.date[0]) ? latestContext.date : "---";
    s.drawString(dateStr, CX, CY + 30);

    // Cat + mouse mascots
    mouseDraw(s, bgCol);
    catDraw(s, bgCol);

    if (useSprite) sprite.pushSprite(0, 0);
}

void renderPomodoro(const display::PomodoroData& data) {
    tft.fillScreen(COL_BG);

    // Phase label
    tft.setTextDatum(lgfx::middle_center);
    tft.setTextSize(3);
    bool isFocus = (strcmp(data.phaseLabel, "focus") == 0 || strcmp(data.phaseLabel, "work") == 0);
    tft.setTextColor(isFocus ? COL_ACCENT : COL_CALM);
    tft.drawString(isFocus ? "FOCUS" : "BREAK", CX, 60);

    // Large countdown
    tft.setTextSize(6);
    tft.setTextColor(COL_FACE);
    uint16_t min = data.remainingSeconds / 60;
    uint16_t sec = data.remainingSeconds % 60;
    char timeBuf[8];
    snprintf(timeBuf, sizeof(timeBuf), "%02d:%02d", min, sec);
    tft.drawString(timeBuf, CX, CY);

    // Cycle dots
    int dotY = CY + 60;
    for (uint8_t i = 0; i < data.totalCycles; i++) {
        uint16_t col = (i < data.currentCycle) ? COL_ACCENT : COL_DIM;
        tft.fillCircle(CX - 30 + (i * 20), dotY, 6, col);
    }
}

void renderReminder(const display::ReminderData& data) {
    LGFX_Sprite& s = sprite.getBuffer() ? sprite : (LGFX_Sprite&)tft;
    bool useSprite = (sprite.getBuffer() != nullptr);

    if (useSprite) s.fillSprite(COL_BG);
    else           tft.fillScreen(COL_BG);

    // Body text — same layout as TEXT_RESPONSE for consistency.
    // Font2 ~18px, word-wrapped, each line centered horizontally,
    // block centered vertically in the body area.
    s.setFont(&fonts::Font2);
    s.setTextSize(1.3f);
    s.setTextColor(COL_FACE);

    const int padX    = 14;
    const int lineH   = 22;
    const int maxW    = LCD_WIDTH - padX * 2;
    const int areaTop = 32;
    const int areaBot = LCD_HEIGHT - 24;
    const int availH  = areaBot - areaTop;

    // ── Word-wrap ──
    char buf[128];
    strncpy(buf, data.text, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';

    char  lines[16][72];
    memset(lines, 0, sizeof(lines));
    int   lineCount = 0;
    char  cur[72]   = {};
    char* word      = strtok(buf, " ");
    while (word && lineCount < 15) {
        char test[72];
        if (cur[0] == '\0') strncpy(test, word, sizeof(test) - 1);
        else                snprintf(test, sizeof(test), "%s %s", cur, word);
        test[sizeof(test) - 1] = '\0';
        if (s.textWidth(test) > maxW && cur[0] != '\0') {
            strncpy(lines[lineCount++], cur, sizeof(lines[0]) - 1);
            strncpy(cur, word, sizeof(cur) - 1);
        } else {
            strncpy(cur, test, sizeof(cur) - 1);
        }
        cur[sizeof(cur) - 1] = '\0';
        word = strtok(nullptr, " ");
    }
    if (cur[0] != '\0') strncpy(lines[lineCount++], cur, sizeof(lines[0]) - 1);

    // ── Vertically center the text block ──
    int totalH = lineCount * lineH;
    int startY = areaTop + (availH - totalH) / 2;

    // ── Render lines ──
    s.setTextDatum(lgfx::top_center);
    for (int i = 0; i < lineCount; i++) {
        s.drawString(lines[i], CX, startY + i * lineH);
    }

    // ── Header on top (same as text response) ──
    s.fillRect(0, 0, LCD_WIDTH, areaTop, COL_BG);
    s.setFont(&fonts::Font2);
    s.setTextSize(1);
    s.setTextDatum(lgfx::middle_center);
    s.setTextColor(COL_ACCENT);
    s.drawString("Aksa", CX, 14);
    s.drawFastHLine(20, 26, LCD_WIDTH - 40, COL_DIM);

    // ── Dismiss hint ──
    s.setTextDatum(lgfx::middle_center);
    s.setTextColor(COL_DIM);
    s.drawString("tap to dismiss", CX, LCD_HEIGHT - 12);
    s.setTextDatum(lgfx::top_left);

    if (useSprite) sprite.pushSprite(0, 0);
}

void renderCountdown(const display::CountdownData& data) {
    tft.fillScreen(COL_BG);

    // Large number
    tft.setTextDatum(lgfx::middle_center);
    tft.setTextSize(8);
    tft.setTextColor(COL_CALM);
    char numBuf[4];
    snprintf(numBuf, sizeof(numBuf), "%d", data.remainingSeconds);
    tft.drawString(numBuf, CX, CY - 20);

    // Instruction
    tft.setTextSize(2);
    tft.setTextColor(COL_FACE);
    tft.drawString(data.instruction, CX, CY + 50);
}

void renderStatus(const display::StatusBar& status) {
    tft.fillScreen(COL_BG);
    tft.setTextDatum(lgfx::middle_center);

    int y = 40;
    const int lineH = 32;

    tft.setTextSize(2);
    tft.setTextColor(COL_ACCENT);
    tft.drawString("System Status", CX, y); y += lineH + 6;

    tft.drawFastHLine(30, y - lineH / 2, LCD_WIDTH - 60, COL_DIM);

    tft.setTextColor(COL_FACE);
    tft.drawString(status.wifiConnected ? "WiFi: Connected" : "WiFi: Offline", CX, y);
    y += lineH;

    tft.drawString(status.wsConnected ? "Backend: Online" : "Backend: Offline", CX, y);
    y += lineH;

    const char* sigLabel = (status.wifiRssi > -50) ? "Excellent" : (status.wifiRssi > -60) ? "Good" :
                           (status.wifiRssi > -70) ? "Fair" : (status.wifiRssi > -80) ? "Weak" : "Poor";
    char rssBuf[32];
    snprintf(rssBuf, sizeof(rssBuf), "Signal: %s (%d)", sigLabel, status.wifiRssi);
    tft.drawString(rssBuf, CX, y); y += lineH;

    if (status.batteryPercent == 255) {
        tft.drawString("Power: USB", CX, y);
    } else {
        char batBuf[16];
        snprintf(batBuf, sizeof(batBuf), "Battery: %d%%", status.batteryPercent);
        tft.drawString(batBuf, CX, y);
    }

    tft.setTextDatum(lgfx::top_left);  // restore default
}

/// Draw transcript overlay into a target (sprite or tft), with auto-scroll support.
void renderTranscriptOverlay(LGFX_Sprite& target, const char* text) {
    const int padX          = 8;
    const int padY          = 5;
    const int lineH         = 14;
    const int visibleLines  = 3;
    const int maxTotalLines = 16;   // word-wrap cap — ~384 chars / ~24 chars avg word
    const int maxCharsPerLine = 36;

    target.setFont(&fonts::Font2);
    target.setTextSize(1);
    target.setTextDatum(lgfx::top_left);

    // Word-wrap entire text into allLines[]
    char allLines[maxTotalLines][42];
    int  totalLines = 0;
    memset(allLines, 0, sizeof(allLines));

    const char* p = text;
    int col = 0;

    while (*p && totalLines < maxTotalLines) {
        while (*p == ' ') p++;
        if (!*p) break;

        const char* wordStart = p;
        while (*p && *p != ' ') p++;
        int wordLen = p - wordStart;

        if (col + (col > 0 ? 1 : 0) + wordLen > maxCharsPerLine) {
            totalLines++;
            col = 0;
            if (totalLines >= maxTotalLines) break;
        }

        if (col > 0) allLines[totalLines][col++] = ' ';

        int copyLen = (col + wordLen < (int)sizeof(allLines[0]) - 1)
                      ? wordLen
                      : ((int)sizeof(allLines[0]) - 1 - col);
        memcpy(&allLines[totalLines][col], wordStart, copyLen);
        col += copyLen;
        allLines[totalLines][col] = '\0';
    }
    if (col > 0) totalLines++;

    // Cache total line count so tick() knows when to stop scrolling
    transcriptTotalLines = totalLines;

    // Clamp scroll offset (guard against stale value after text change)
    int maxScroll = totalLines - visibleLines;
    if (maxScroll < 0) maxScroll = 0;
    if (transcriptScrollLine > maxScroll) transcriptScrollLine = maxScroll;

    int drawCount = totalLines - transcriptScrollLine;
    if (drawCount > visibleLines) drawCount = visibleLines;

    int barH = padY * 2 + drawCount * lineH;
    int barY = LCD_HEIGHT - barH;

    target.fillRect(0, barY, LCD_WIDTH, barH, COL_STATUS_BG);

    target.setTextColor(COL_FACE);
    for (int i = 0; i < drawCount; i++) {
        target.drawString(allLines[transcriptScrollLine + i], padX, barY + padY + i * lineH);
    }
}

void renderTextResponse() {
    LGFX_Sprite& s = sprite.getBuffer() ? sprite : (LGFX_Sprite&)tft;
    bool useSprite = (sprite.getBuffer() != nullptr);

    if (useSprite) s.fillSprite(COL_BG);
    else           tft.fillScreen(COL_BG);

    // Body text — Font2 ~18px, word-wrapped, lines centered horizontally.
    // Rendered before the header so scrolled text can't bleed over the "Aksa" label.
    s.setFont(&fonts::Font2);
    s.setTextSize(1.3f);
    s.setTextColor(COL_FACE);

    const int   padX    = 14;
    const int   lineH   = 22;
    const int   maxW    = LCD_WIDTH - padX * 2;
    const int   areaTop = 32;   // below separator
    const int   areaBot = LCD_HEIGHT - 24;
    const int   availH  = areaBot - areaTop;

    // ── Word-wrap: build line array ──
    char buf[1024];
    strncpy(buf, textResponseBuf, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';

    char  lines[32][72];
    memset(lines, 0, sizeof(lines));
    int   lineCount = 0;
    char  cur[72]   = {};
    char* word      = strtok(buf, " ");
    while (word && lineCount < 31) {
        char test[72];
        if (cur[0] == '\0') strncpy(test, word, sizeof(test) - 1);
        else                snprintf(test, sizeof(test), "%s %s", cur, word);
        test[sizeof(test) - 1] = '\0';
        if (s.textWidth(test) > maxW && cur[0] != '\0') {
            strncpy(lines[lineCount++], cur, sizeof(lines[0]) - 1);
            strncpy(cur, word, sizeof(cur) - 1);
        } else {
            strncpy(cur, test, sizeof(cur) - 1);
        }
        cur[sizeof(cur) - 1] = '\0';
        word = strtok(nullptr, " ");
    }
    if (cur[0] != '\0') strncpy(lines[lineCount++], cur, sizeof(lines[0]) - 1);

    int totalH = lineCount * lineH;

    // ── Scroll / center ──
    uint32_t now    = millis();
    int      startY = areaTop;

    if (totalH <= availH) {
        // Content fits — center the block vertically
        startY           = areaTop + (availH - totalH) / 2;
        textScrollPx     = 0.0f;
        textScrollLastMs = 0;
    } else {
        // Content overflows — auto-scroll after response is complete
        if (textResponseComplete) {
            if (textScrollLastMs == 0) textScrollLastMs = now;  // first frame
            float dt = (now - textScrollLastMs) / 1000.0f;
            textScrollLastMs = now;
            float maxScroll = (float)(totalH - availH);
            textScrollPx = fminf(textScrollPx + TEXT_SCROLL_SPEED * dt, maxScroll);
        }
        startY = areaTop - (int)textScrollPx;
    }

    // ── Render lines (skip those fully outside body area) ──
    s.setTextDatum(lgfx::top_center);
    for (int i = 0; i < lineCount; i++) {
        int y = startY + i * lineH;
        if (y + lineH <= areaTop) continue;   // fully above visible area
        if (y >= areaBot)          break;      // below visible area
        s.drawString(lines[i], CX, y);
    }

    // ── Re-draw header on top so scrolled lines can't bleed over "Aksa" label ──
    s.fillRect(0, 0, LCD_WIDTH, areaTop, COL_BG);
    s.setFont(&fonts::Font2);
    s.setTextSize(1);
    s.setTextDatum(lgfx::middle_center);
    s.setTextColor(COL_ACCENT);
    s.drawString("Aksa", CX, 14);
    s.drawFastHLine(20, 26, LCD_WIDTH - 40, COL_DIM);

    // ── Dismiss hint — only once complete and scroll has reached the end ──
    bool scrollDone = (totalH <= availH) ||
                      (textScrollPx >= (float)(totalH - availH) - 1.0f);
    if (textResponseComplete && scrollDone) {
        s.setTextDatum(lgfx::middle_center);
        s.setTextColor(COL_DIM);
        s.drawString("tap to dismiss", CX, LCD_HEIGHT - 12);
    }
    s.setTextDatum(lgfx::top_left);

    if (useSprite) sprite.pushSprite(0, 0);
}

void renderGlance(const display::GlanceData& data) {
    LGFX_Sprite& s = sprite.getBuffer() ? sprite : (LGFX_Sprite&)tft;
    bool useSprite = (sprite.getBuffer() != nullptr);

    if (useSprite) s.fillSprite(COL_BG);
    else           tft.fillScreen(COL_BG);

    // ── Large time (live-ticking — seeded by context:sync, advances locally) ──
    char liveBuf[8];
    if (syncedAtMs > 0) {
        uint32_t elapsedMin = (millis() - syncedAtMs) / 60000;
        uint32_t totalMin   = (syncedMinutes + elapsedMin) % (24 * 60);
        uint8_t  lh         = (uint8_t)(totalMin / 60);
        uint8_t  lm         = (uint8_t)(totalMin % 60);
        snprintf(liveBuf, sizeof(liveBuf), "%02d:%02d", lh, lm);
    } else {
        strncpy(liveBuf, data.time, sizeof(liveBuf) - 1);
        liveBuf[sizeof(liveBuf) - 1] = '\0';
    }
    s.setTextDatum(lgfx::middle_center);
    s.setFont(&fonts::Font0);
    s.setTextSize(6);
    s.setTextColor(COL_FACE);
    s.drawString(liveBuf, CX, 80);

    // ── Date ──
    s.setTextSize(2);
    s.setTextColor(COL_DIM);
    s.drawString(data.date, CX, 120);

    if (data.hasWeather) {
        // ── Divider line ──
        s.drawFastHLine(60, 150, 120, COL_DIM);

        // ── Weather icon (text-based) ──
        const char* icon = "?";
        uint8_t code = data.weatherCode;
        if (code == 0)        icon = "*";   // Clear/sun
        else if (code <= 3)   icon = "~";   // Partly cloudy
        else if (code <= 49)  icon = "=";   // Foggy
        else if (code <= 69)  icon = ",";   // Rain/drizzle
        else if (code <= 79)  icon = ".";   // Snow
        else if (code <= 86)  icon = ",";   // Showers
        else if (code >= 95)  icon = "!";   // Thunderstorm

        // Temperature — large and prominent
        char tempBuf[8];
        snprintf(tempBuf, sizeof(tempBuf), "%d%cC", data.temp, 0xB0);  // degree symbol

        s.setTextSize(4);
        s.setTextColor(PAL[0].accent);  // Cyan from IDLE palette
        s.drawString(tempBuf, CX, 190);

        // Weather description
        s.setTextSize(2);
        s.setTextColor(COL_DIM);
        s.drawString(data.weather, CX, 230);

        // Humidity
        char humBuf[12];
        snprintf(humBuf, sizeof(humBuf), "%d%% humid", data.humidity);
        s.setTextSize(1);
        s.setTextColor(COL_DIM);
        s.drawString(humBuf, CX, 260);
    }

    if (useSprite) s.pushSprite(0, 0);
}

}  // namespace display_hw

// ── Public API ─────────────────────────────────────────

void display::setHomeMode(Mode mode) {
    g_homeMode = mode;
    setMode(mode);
}

display::Mode display::getHomeMode() {
    return g_homeMode;
}

void display::setFaceStyle(uint8_t styleId) {
    g_faceStyle = face_style::fromId(styleId);
    Serial.printf("[Display] Face style: %s\n", g_faceStyle->name);
}

uint8_t display::getFaceStyleId() {
    return static_cast<uint8_t>(g_faceStyle->id);
}

void display::setFaceColors(uint32_t bgColor, uint32_t eyeBodyColor, uint32_t mouthColor) {
    g_faceBgColor    = bgColor & 0x00FFFFFFu;
    {
        uint8_t r = (eyeBodyColor >> 16) & 0xFF;
        uint8_t g = (eyeBodyColor >>  8) & 0xFF;
        uint8_t b =  eyeBodyColor        & 0xFF;
        g_faceEyeBody565 = rgb(r, g, b);
    }
    {
        uint8_t r = (mouthColor >> 16) & 0xFF;
        uint8_t g = (mouthColor >>  8) & 0xFF;
        uint8_t b =  mouthColor        & 0xFF;
        g_faceMouth565 = rgb(r, g, b);
    }
    Serial.printf("[Display] Face colors: bg=#%06lX eye=#%06lX mouth=#%06lX\n",
                  (unsigned long)g_faceBgColor, (unsigned long)eyeBodyColor, (unsigned long)mouthColor);
}

// ── Image dimension helpers ──────────────────────────────────────────────────
// Parse just the header bytes to get width/height before decoding.
// Lets us compute a "contain" scale without a full decode pass.

static bool jpegDimensions(const uint8_t* buf, size_t len, int& w, int& h) {
    // Walk JPEG markers: SOI (FF D8) then [FF][marker][len(2)][data...]
    // SOF0/1/2/3 (FF C0-C3) carry height/width.
    size_t i = 2; // skip SOI
    while (i + 4 < len) {
        if (buf[i] != 0xFF) return false;
        uint8_t marker = buf[i + 1];
        if (marker >= 0xC0 && marker <= 0xC3) { // SOF0/1/2/3
            if (i + 9 >= len) return false;
            h = (buf[i + 5] << 8) | buf[i + 6];
            w = (buf[i + 7] << 8) | buf[i + 8];
            return (w > 0 && h > 0);
        }
        uint16_t segLen = (buf[i + 2] << 8) | buf[i + 3];
        i += 2 + segLen;
    }
    return false;
}

static bool pngDimensions(const uint8_t* buf, size_t len, int& w, int& h) {
    // PNG: 8-byte signature, then IHDR chunk: [len(4)]["IHDR"][width(4)][height(4)]
    if (len < 24) return false;
    w = (buf[16] << 24) | (buf[17] << 16) | (buf[18] << 8) | buf[19];
    h = (buf[20] << 24) | (buf[21] << 16) | (buf[22] << 8) | buf[23];
    return (w > 0 && h > 0);
}

static bool bmpDimensions(const uint8_t* buf, size_t len, int& w, int& h) {
    // BMP: signature "BM" then BITMAPFILEHEADER (14 bytes), then BITMAPINFOHEADER
    // width at offset 18, height at offset 22 (both little-endian signed 32-bit)
    if (len < 26 || buf[0] != 'B' || buf[1] != 'M') return false;
    w = buf[18] | (buf[19] << 8) | (buf[20] << 16) | (buf[21] << 24);
    int raw_h = buf[22] | (buf[23] << 8) | (buf[24] << 16) | (buf[25] << 24);
    h = raw_h < 0 ? -raw_h : raw_h; // negative height = top-down DIB
    return (w > 0 && h > 0);
}

// Compute scale and centered offset so the image fits entirely on screen.
static void containScale(int imgW, int imgH, float& scale, int& offX, int& offY) {
    float sx = (float)LCD_WIDTH  / imgW;
    float sy = (float)LCD_HEIGHT / imgH;
    scale = (sx < sy) ? sx : sy;
    offX  = (LCD_WIDTH  - (int)(imgW * scale)) / 2;
    offY  = (LCD_HEIGHT - (int)(imgH * scale)) / 2;
}

// ────────────────────────────────────────────────────────────────────────────

void display::showImageFromSD(const char* path, uint16_t durationMs) {
    if (!path || !*path) return;

    // Determine image format from extension first — fail fast before touching display
    const char* ext = strrchr(path, '.');
    if (!ext) {
        Serial.printf("[Display] showImageFromSD: no extension in path: %s\n", path);
        return;
    }

    // Switch to IMAGE mode BEFORE drawing. Both showImageFromSD (called from
    // wsLoop) and displayLoop run on Core 1. FreeRTOS can preempt wsLoop at
    // any 1ms tick boundary, allowing displayLoop to push a face sprite over a
    // partially-drawn image. Setting currentMode = IMAGE first causes tick() to
    // return early, so the TFT is ours for the duration of the draw.
    if (durationMs > 0) {
        setModeTemporary(Mode::IMAGE, durationMs);
    } else {
        setMode(Mode::IMAGE);
    }

    // Wake the display if it's sleeping (setModeTemporary already calls wake if sleeping)
    if (sleeping) wake();

    // Fill screen black before drawing
    tft.fillScreen(TFT_BLACK);

    // LovyanGFX's drawXxxFile(fs, path) template has no DataWrapperT specialisation
    // for fs::SDMMCFS — it only works with SPIFFS/SPI-SD.  Read the file into
    // PSRAM first, then use the in-memory draw variants.
    File imgFile = SD_MMC.open(path, FILE_READ);
    if (!imgFile) {
        Serial.printf("[Display] showImageFromSD: open failed: %s\n", path);
        currentMode = previousMode;
        autoReturnActive = false;
        return;
    }
    size_t fileSize = imgFile.size();
    if (fileSize == 0 || fileSize > 2 * 1024 * 1024) {
        Serial.printf("[Display] showImageFromSD: bad size %u for %s\n",
                      (unsigned)fileSize, path);
        imgFile.close();
        currentMode = previousMode;
        autoReturnActive = false;
        return;
    }
    uint8_t* buf = (uint8_t*)ps_malloc(fileSize);
    if (!buf) {
        Serial.printf("[Display] showImageFromSD: PSRAM alloc failed (%u bytes)\n",
                      (unsigned)fileSize);
        imgFile.close();
        currentMode = previousMode;
        autoReturnActive = false;
        return;
    }
    imgFile.read(buf, fileSize);
    imgFile.close();

    // Parse dimensions and compute "contain" scale + centering offset
    int imgW = 0, imgH = 0;
    float scale = 1.0f;
    int offX = 0, offY = 0;
    bool gotDims = false;
    if (strcasecmp(ext, ".jpg") == 0 || strcasecmp(ext, ".jpeg") == 0)
        gotDims = jpegDimensions(buf, fileSize, imgW, imgH);
    else if (strcasecmp(ext, ".png") == 0)
        gotDims = pngDimensions(buf, fileSize, imgW, imgH);
    else if (strcasecmp(ext, ".bmp") == 0)
        gotDims = bmpDimensions(buf, fileSize, imgW, imgH);

    if (gotDims) {
        containScale(imgW, imgH, scale, offX, offY);
        Serial.printf("[Display] image %dx%d → scale %.3f, offset (%d,%d)\n",
                      imgW, imgH, scale, offX, offY);
    }

    bool ok = false;
    if (strcasecmp(ext, ".jpg") == 0 || strcasecmp(ext, ".jpeg") == 0) {
        // scale_y=0 in LovyanGFX means "same as scale_x"
        ok = tft.drawJpg(buf, fileSize, offX, offY, 0, 0, 0, 0, scale, 0.0f);
    } else if (strcasecmp(ext, ".bmp") == 0) {
        ok = tft.drawBmp(buf, fileSize, offX, offY, 0, 0, 0, 0, scale, 0.0f);
    } else if (strcasecmp(ext, ".png") == 0) {
        ok = tft.drawPng(buf, fileSize, offX, offY, 0, 0, 0, 0, scale, 0.0f);
    } else {
        Serial.printf("[Display] showImageFromSD: unsupported format: %s\n", ext);
        free(buf);
        currentMode = previousMode;
        autoReturnActive = false;
        return;
    }
    free(buf);

    if (!ok) {
        Serial.printf("[Display] showImageFromSD: draw failed for: %s\n", path);
        currentMode = previousMode;
        autoReturnActive = false;
        return;
    }

    Serial.printf("[Display] showImageFromSD: showing %s for %ums\n", path, (unsigned)durationMs);
    // Mode already set above — displayLoop skips rendering until timer expires
}

void display::init() {
    display_hw::init();
    face::init();

    currentMode = Mode::FACE;
    sleeping = false;
    brightness = userBrightness;
    display_hw::setBacklight(brightness);

    Serial.println("[Display] Initialized — face mode");
}

void display::tick(uint32_t nowMs) {
    // Always advance fade — even while sleeping (fade-out needs to run)
    if (fadeActive) {
        uint32_t elapsed = nowMs - fadeStartMs;
        if (elapsed >= fadeDurationMs) {
            // Fade complete
            brightness = fadeTo;
            display_hw::setBacklight(brightness);
            fadeActive = false;
        } else {
            // Lerp brightness
            float t = (float)elapsed / (float)fadeDurationMs;
            // Ease-in-out (smoothstep)
            t = t * t * (3.0f - 2.0f * t);
            uint8_t current = fadeFrom + (uint8_t)((int16_t)(fadeTo - fadeFrom) * t);
            display_hw::setBacklight(current);
        }
    }

    if (sleeping) return;

    // Transcript auto-scroll — advance one line every TRANSCRIPT_SCROLL_INTERVAL_MS
    // while there are off-screen lines remaining.
    if (transcriptEnabled && transcriptText[0] != '\0') {
        int maxScroll = transcriptTotalLines - 3;  // 3 = visibleLines
        if (maxScroll > 0 && transcriptScrollLine < maxScroll) {
            if (nowMs - transcriptScrollMs >= TRANSCRIPT_SCROLL_INTERVAL_MS) {
                transcriptScrollLine++;
                transcriptScrollMs = nowMs;
            }
        }
    }

    // Auto-return timer — must run in every mode including IMAGE.
    // Previously this was inside the rate-limited block below, which IMAGE mode
    // never reached, so the timer never fired and images stayed forever.
    if (autoReturnActive && nowMs >= autoReturnAtMs) {
        autoReturnActive = false;
        currentMode = previousMode;
        if (g_onModeChange) g_onModeChange(modeToString(currentMode));
    }

    // TEXT_RESPONSE auto-return after linger period
    if (currentMode == Mode::TEXT_RESPONSE && textResponseComplete) {
        if (nowMs - textResponseCompleteMs >= TEXT_RESPONSE_LINGER_MS) {
            textResponseBuf[0]   = '\0';
            textResponseComplete = false;
            currentMode = previousMode;
            if (g_onModeChange) g_onModeChange(modeToString(currentMode));
        }
    }

    // IMAGE mode: image drawn directly to TFT hardware — skip sprite rendering
    // to avoid overwriting it.
    if (currentMode == Mode::IMAGE) return;

    // Rate-limit rendering
    if ((nowMs - lastRenderMs) < RENDER_INTERVAL_MS) return;
    lastRenderMs = nowMs;

    // Advance face animation
    face::tick(nowMs);

    // Render current mode
    switch (currentMode) {
        case Mode::FACE:
            display_hw::renderFace(face::getState(), statusBar);
            break;
        case Mode::CLOCK:
            display_hw::renderClock(statusBar);
            break;
        case Mode::POMODORO:
            display_hw::renderPomodoro(pomodoroData);
            break;
        case Mode::REMINDER:
            display_hw::renderReminder(reminderData);
            break;
        case Mode::COUNTDOWN:
            display_hw::renderCountdown(countdownData);
            break;
        case Mode::STATUS:
            display_hw::renderStatus(statusBar);
            break;
        case Mode::GLANCE:
            display_hw::renderGlance(glanceData);
            break;
        case Mode::TEXT_RESPONSE:
            display_hw::renderTextResponse();
            break;
    }

}

void display::setMode(Mode mode) {
    if (mode == currentMode && !autoReturnActive) return;
    previousMode = currentMode;
    currentMode = mode;
    autoReturnActive = false;
    if (mode == Mode::CLOCK) { g_clockDirty = true; g_catInited = false; }
    if (sleeping) wake();
    if (g_onModeChange) g_onModeChange(modeToString(mode));
}

display::Mode display::getMode() {
    return currentMode;
}

void display::setModeTemporary(Mode mode, uint16_t durationMs) {
    previousMode = currentMode;
    currentMode = mode;
    autoReturnActive = true;
    autoReturnAtMs = millis() + durationMs;
    if (mode == Mode::CLOCK) g_clockDirty = true;
    if (sleeping) wake();
    if (g_onModeChange) g_onModeChange(modeToString(mode));
}

void display::updateStatusBar(const StatusBar& status) {
    statusBar = status;
}

void display::showPomodoro(const PomodoroData& data) {
    pomodoroData = data;
    setMode(Mode::POMODORO);
}

void display::showReminder(const ReminderData& data) {
    reminderData = data;
    setModeTemporary(Mode::REMINDER, data.durationMs > 0 ? data.durationMs : 5000);
}

void display::showCountdown(const CountdownData& data) {
    countdownData = data;
    setMode(Mode::COUNTDOWN);
}

void display::setTranscriptOverlay(bool enabled) {
    transcriptEnabled = enabled;
}

/// Strip markdown syntax characters from `src` into `dst` (max `dstSize` bytes).
/// Removes: * _ ` ~ (formatting), leading # (headers), > (blockquotes).
/// Keeps the text content — only drops the surrounding symbols.
static void stripMarkdown(const char* src, char* dst, size_t dstSize) {
    const char* r = src;
    char* w = dst;
    char* end = dst + dstSize - 1;  // leave room for '\0'

    // Skip leading "# " header markers (e.g. "## Title" → "Title")
    while (*r == '#') r++;
    if (r > src && *r == ' ') r++;  // consume the space after hashes

    while (*r && w < end) {
        char c = *r;

        // Skip blockquote marker at line start ("> ")
        if (c == '>' && (r == src || *(r - 1) == '\n')) {
            r++;
            if (*r == ' ') r++;  // consume the space after >
            continue;
        }

        // Skip markdown formatting symbols: * _ ` ~
        if (c == '*' || c == '_' || c == '`' || c == '~') {
            r++;
            continue;
        }

        *w++ = c;
        r++;
    }

    // Trim trailing whitespace
    while (w > dst && *(w - 1) == ' ') w--;

    *w = '\0';
}

void display::setTranscriptText(const char* text) {
    stripMarkdown(text, transcriptText, sizeof(transcriptText));
    // Reset scroll to top whenever text changes (new sentence / STT update)
    transcriptScrollLine = 0;
    transcriptScrollMs   = millis();
}

void display::appendTextResponse(const char* text) {
    if (!text || !text[0]) return;
    // Start fresh if the previous response was already complete
    if (textResponseComplete) {
        textResponseBuf[0]   = '\0';
        textResponseComplete = false;
        textScrollPx         = 0.0f;
        textScrollLastMs     = 0;
    }
    // Strip markdown and append with a space separator between sentences
    char stripped[256];
    stripMarkdown(text, stripped, sizeof(stripped));
    if (textResponseBuf[0] != '\0') {
        strncat(textResponseBuf, " ", sizeof(textResponseBuf) - strlen(textResponseBuf) - 1);
    }
    strncat(textResponseBuf, stripped, sizeof(textResponseBuf) - strlen(textResponseBuf) - 1);
    // Switch to TEXT_RESPONSE mode — saves previousMode on first call of a new response
    if (currentMode != Mode::TEXT_RESPONSE) {
        setMode(Mode::TEXT_RESPONSE);
    }
}

void display::finalizeTextResponse() {
    textResponseComplete   = true;
    textResponseCompleteMs = millis();
}

void display::clearTextResponse() {
    textResponseBuf[0]   = '\0';
    textResponseComplete = false;
    textScrollPx         = 0.0f;
    textScrollLastMs     = 0;
    setMode(previousMode);
}

void display::setBrightness(uint8_t level) {
    userBrightness = level;
    brightness = level;
    if (!fadeActive) {
        display_hw::setBacklight(level);
    }
}

void display::fadeBrightness(uint8_t target, uint16_t durationMs) {
    if (target == brightness && !fadeActive) return;

    // Snapshot current actual brightness as the fade start point
    if (fadeActive) {
        // Mid-fade: interpolate where we are right now
        uint32_t elapsed = millis() - fadeStartMs;
        float t = (float)elapsed / (float)fadeDurationMs;
        if (t > 1.0f) t = 1.0f;
        t = t * t * (3.0f - 2.0f * t);  // smoothstep
        fadeFrom = fadeFrom + (uint8_t)((int16_t)(fadeTo - fadeFrom) * t);
    } else {
        fadeFrom = brightness;
    }
    fadeTo = target;
    fadeStartMs = millis();
    fadeDurationMs = durationMs > 0 ? durationMs : 1;
    fadeActive = true;
}

bool display::isFading() {
    return fadeActive;
}

bool display::isSleeping() {
    return sleeping;
}

void display::sleep() {
    if (sleeping) return;
    sleeping = true;
    face::setExpression(face::Expression::SLEEPING, 500);
    fadeBrightness(0, 200);
}

void display::wake() {
    if (!sleeping) return;
    sleeping = false;
    face::setExpression(face::Expression::IDLE, 300);
    setMode(g_homeMode);  // restore to user's configured idle mode, not always FACE
    // Don't set brightness before fade — fadeBrightness checks target == brightness
    // and skips if they match. We need it to fade FROM current (0) TO userBrightness.
    fadeBrightness(userBrightness, 300);
}

void display::updateContextData(const GlanceData& data) {
    latestContext = data;
    contextDataAvailable = true;

    // Seed the live clock — parse "HH:MM" and record millis() right now
    int h = 0, m = 0;
    if (sscanf(data.time, "%d:%d", &h, &m) == 2) {
        syncedMinutes = (uint32_t)(h * 60 + m);
        syncedAtMs    = millis();
    }
}

void display::showGlance() {
    if (!contextDataAvailable) return;
    glanceData = latestContext;
    setModeTemporary(Mode::GLANCE, 8000);
}

bool display::hasContextData() {
    return contextDataAvailable;
}

void display::setBiosOverlay(const char* title, const char* counter,
                             const char* navL, const char* navC, const char* navR) {
    g_biosOverlay.enabled = true;
    strncpy(g_biosOverlay.title,   title   ? title   : "", sizeof(g_biosOverlay.title)   - 1);
    strncpy(g_biosOverlay.counter, counter ? counter : "", sizeof(g_biosOverlay.counter) - 1);
    strncpy(g_biosOverlay.navL,    navL    ? navL    : "", sizeof(g_biosOverlay.navL)    - 1);
    strncpy(g_biosOverlay.navC,    navC    ? navC    : "", sizeof(g_biosOverlay.navC)    - 1);
    strncpy(g_biosOverlay.navR,    navR    ? navR    : "", sizeof(g_biosOverlay.navR)    - 1);
}

void display::clearBiosOverlay() {
    g_biosOverlay.enabled = false;
}

