#include "display.h"
#include "face.h"
#include "face_style.h"
#include "config.h"
#include "lgfx_config.h"
#include <Arduino.h>
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

static bool sleeping = false;
static uint8_t brightness = 70;       // Current/target brightness for the HW
static uint8_t userBrightness = 70;   // User-set brightness (survives sleep)
static bool transcriptEnabled = false;
static char transcriptText[128] = {};

// Auto-return timer
static bool autoReturnActive = false;
static uint32_t autoReturnAtMs = 0;

// Rendering rate control
static uint32_t lastRenderMs = 0;
static const uint16_t RENDER_INTERVAL_MS = 33;  // ~30fps

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

// ── Active face style ─────────────────────────────────
// Points to one of the built-in presets (ORBIT or NOVA).
// Changed at runtime via display::setFaceStyle() — loaded from NVS on boot.
static const face_style::FaceStyleDef* g_faceStyle = &face_style::NOVA;

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

// V2 eye — rounded rectangle style shared across expressions.
//
// scaleY      — blink scale (1=open, 0=closed), same contract as drawEyeOpen
// driftX/Y    — gaze drift: shifts the whole rect (no pupil)
// squintBot   — 0=flat bottom (idle), 1=bottom lid fully risen (big grin).
//               The top stays fixed; only the bottom half shrinks.
// eyeW/eyeH   — per-expression eye dimensions (defaults: 54×30)
static void drawEyeV2(LGFX_Sprite& s, int cx, int cy,
                      float scaleY, float driftX, float driftY,
                      float squintBot = 0.0f,
                      int eyeW = 68, int eyeH = 38) {
    static const int CR     = 8;
    static const int MAX_DX = 10;
    static const int MAX_DY = 5;
    static const uint16_t EYE_COL = rgb(218, 220, 230);

    int ox = constrain((int)driftX, -MAX_DX, MAX_DX);
    int oy = constrain((int)driftY, -MAX_DY, MAX_DY);
    int ex = cx + ox;
    int ey = cy + oy;

    // Top half-height: driven by blink
    int hhTop = (int)((eyeH / 2) * scaleY);
    // Bottom half-height: additionally closes upward with squintBot
    int hhBot = (int)(hhTop * (1.0f - squintBot));
    int totalH = hhTop + hhBot;

    if (totalH < 2) {
        s.fillRoundRect(ex - eyeW / 2, ey - 1, eyeW, 2, 1, EYE_COL);
        return;
    }

    int actualCR = CR;
    if (actualCR > hhBot)  actualCR = (hhBot  > 1) ? hhBot  - 1 : 1;
    if (actualCR > hhTop)  actualCR = (hhTop  > 1) ? hhTop  - 1 : 1;
    s.fillRoundRect(ex - eyeW / 2, ey - hhTop, eyeW, totalH, actualCR, EYE_COL);
}

static void drawEyeOpen(LGFX_Sprite& s, int cx, int cy, const EyeShape& eye,
                         float scaleY, float pupilDX, float pupilDY) {
    int r = eye.r;
    int rh = (int)(r * scaleY);
    if (rh < 4) {
        thickBezier(s, cx - r, cy, cx, cy + 4, cx + r, cy, 2, TFT_WHITE, 16);
        return;
    }
    if (rh < r) s.fillEllipse(cx, cy, r, rh, TFT_WHITE);
    else        s.fillSmoothCircle(cx, cy, r, TFT_WHITE);

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
    thickBezier(s, cx - r, cy, cx, cy + bend, cx + r, cy, 2, TFT_WHITE, 20);
}

static void drawEyeX(LGFX_Sprite& s, int cx, int cy, int size, uint16_t color) {
    int hs = size / 2;
    for (int i = -2; i <= 2; i++) {
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
                    // Flat wide rounded rect with subtle breathe variation
                    float breathOff = sinf(breathPhase * 2 * 3.14159f) * 1.5f;
                    int mw = 52, mh = 7 + (int)breathOff;
                    if (mh < 5) mh = 5;
                    s.fillRoundRect(CX - mw / 2, my - mh / 2, mw, mh, mh / 2, pal.mouth);
                } else {
                    float breathOff = sinf(breathPhase * 2 * 3.14159f) * 1.5f;
                    thickBezier(s, CX - 30, my, CX, my + 10 + breathOff, CX + 30, my, 3, pal.mouth);
                }
            }
            break;
        }
        case face::Expression::LISTENING: {
            if (nova) {
                // Small rounded rect dot — attentive pause
                s.fillRoundRect(CX - 8, my - 9, 16, 18, 4, pal.mouth);
                s.fillRoundRect(CX - 4, my - 5, 8, 10, 3, blendRGB565(pal.accent, pal.bg, 40));
            } else {
                s.fillEllipse(CX, my, 7, 9, pal.mouth);
                s.fillEllipse(CX, my, 4, 6, blendRGB565(pal.accent, pal.bg, 40));
            }
            break;
        }
        case face::Expression::THINKING: {
            // Animated pursed lip — shifts side-to-side like "hmm"
            float thinkT = breathPhase * 6.28318f;
            int mxOff = (int)(sinf(thinkT * 1.5f) * 10.0f);
            if (nova) {
                float mOpen = (sinf(thinkT * 2.0f) * 0.5f + 0.5f) * 0.3f;
                int mw = 18 + (int)(mOpen * 10);
                int mh = 8 + (int)(mOpen * 12);
                int cr = mh / 2;
                s.fillRoundRect(CX + mxOff - mw / 2, my - mh / 2, mw, mh, cr, pal.mouth);
                if (mh > 10) {
                    s.fillRoundRect(CX + mxOff - mw / 2 + 3, my - mh / 2 + 3,
                                    mw - 6, mh - 6, cr,
                                    blendRGB565(pal.accent, pal.bg, 30));
                }
            } else {
                float mOpen = (sinf(thinkT * 2.0f) * 0.5f + 0.5f) * 0.3f;
                int mw = 8 + (int)(mOpen * 6);
                int mh = 5 + (int)(mOpen * 8);
                s.fillEllipse(CX + mxOff, my, mw, mh, pal.mouth);
                if (mh > 6) {
                    s.fillEllipse(CX + mxOff, my, mw - 3, mh - 3,
                                  blendRGB565(pal.accent, pal.bg, 30));
                }
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
                    // Wide short rounded rect — happy smile bar
                    int mw = 54, mh = 8;
                    s.fillRoundRect(CX - mw / 2, my + 4, mw, mh, mh / 2, pal.mouth);
                    s.fillRoundRect(CX - mw / 2 + 6, my + 5, mw - 12, 3, 1,
                                    blendRGB565(TFT_WHITE, pal.mouth, 160));
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
                    // Narrow short rect sitting lower — sad flat line
                    float trem = sinf(breathPhase * 6.28318f * 3) * 1.0f;
                    int mw = 30, mh = 6;
                    s.fillRoundRect(CX - mw / 2, my + 2 + (int)trem, mw, mh, mh / 2, pal.mouth);
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
                    // Wide short rect — confident smile bar
                    int mw = 48, mh = 8;
                    s.fillRoundRect(CX - mw / 2, my + 4, mw, mh, mh / 2, pal.mouth);
                    s.fillRoundRect(CX - mw / 2 + 5, my + 5, mw - 10, 3, 1,
                                    blendRGB565(TFT_WHITE, pal.mouth, 120));
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
            // Z text — same for both styles
            float bOff = sinf(breathPhase * 2 * 3.14159f) * 5;
            s.setTextSize(2);
            s.setTextColor(pal.accent);
            s.drawChar('z', CX + 22, my - 5 + (int)bOff);
            s.setTextSize(3);
            s.drawChar('Z', CX + 35, my - 25 + (int)(bOff * 0.7f));
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
                // Tall rounded rect — rectangular O-mouth
                int mw = (int)(44 * pulse);
                int mh = (int)(52 * pulse);
                int cr = mw / 3;
                s.fillRoundRect(CX - mw / 2, my - mh / 2, mw, mh, cr, pal.mouth);
                s.fillRoundRect(CX - mw / 2 + 5, my - mh / 2 + 5, mw - 10, mh - 10, cr,
                                blendRGB565(pal.accent, pal.bg, 25));
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
                // Tall rounded rect with tremor
                int mw = 52;
                int mh = 56 + (int)trem;
                int cr = mw / 3;
                s.fillRoundRect(CX - mw / 2, my - mh / 2 + 4, mw, mh, cr, pal.mouth);
                s.fillRoundRect(CX - mw / 2 + 5, my - mh / 2 + 9, mw - 10, mh - 10, cr,
                                blendRGB565(pal.accent, pal.bg, 20));
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
                    // Narrow short rect — tight angry line
                    int mw = 32, mh = 6;
                    s.fillRoundRect(CX - mw / 2, my + 1, mw, mh, mh / 2, pal.mouth);
                } else {
                    // Tight clenched frown
                    thickBezier(s, CX - 20, my + 2, CX, my - 6, CX + 20, my + 2, 3, pal.mouth);
                    // Teeth-clenched line
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
    const Palette& pal = PAL[exprIdx];
    const EyeShape& eye = EYES[exprIdx];

    // Clear with expression-specific background
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
        float bOff = sinf(fs.breathPhase * 2 * 3.14159f) * 3;
        drawEyeClosed(s, leftEyeX,  eyeY + (int)bOff, 24, false);
        drawEyeClosed(s, rightEyeX, eyeY + (int)bOff, 24, false);
    } else if (fs.expression == face::Expression::OFFLINE) {
        drawEyeOpen(s, leftEyeX, eyeY, leftEye, 1.0f, fs.driftX, fs.driftY);
        drawEyeOpen(s, rightEyeX, eyeY, rightEye, 1.0f, fs.driftX, fs.driftY);
        drawEyeX(s, leftEyeX,  eyeY, 20, pal.accent);
        drawEyeX(s, rightEyeX, eyeY, 20, pal.accent);
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
            drawEyeV2(s, leftEyeX,  eyeY, leftScale,  dx, dy, squint, lw, lh);
            drawEyeV2(s, rightEyeX, eyeY, rightScale, dx, dy, squint, rw, rh);

            if (es.hasBrows || drawPeakBrows) {
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
        int ow = (int)(12 + fs.yawnAmp * 14);
        int oh = (int)(4 + fs.yawnAmp * 20);
        s.fillEllipse(CX, my, ow, oh, pal.mouth);
        uint16_t inside = blendRGB565(pal.accent, pal.bg, 30);
        if (oh > 6) s.fillEllipse(CX, my, ow - 3, oh - 3, inside);
    } else {
        drawMouth(s, fs.expression, pal, fs.mouthAmp, fs.bounceY * ps, fs.breathPhase);
    }
    }
    skip_face:

    // ── Thinking dots (bottom, bouncing with accent color) ──
    if (fs.expression == face::Expression::THINKING) {
        int baseY = LCD_HEIGHT - 42;
        for (int i = 0; i < 3; i++) {
            int dx = CX - 18 + i * 18;
            bool lit = i < fs.thinkDots;
            // Bounce: active dot jumps up
            float bounce = lit ? sinf(fs.glowPhase * 4.0f + i * 0.8f) * 6.0f : 0;
            int dy = baseY - (int)(bounce > 0 ? bounce : 0);
            int r = lit ? 6 : 4;
            uint16_t col = lit ? pal.accent : blendRGB565(pal.accent, pal.bg, 60);
            s.fillSmoothCircle(dx, dy, r, col);
            if (lit) {
                drawGlow(s, dx, dy, 14, pal.accent, pal.bg, 60);
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
    // Blue filled dot = phone present, dim hollow dot = away/unknown
    {
        uint16_t btCol = status.blePresent
            ? rgb(80, 140, 255)                            // blue — present
            : rgb(60, 60, 80);                             // dim — away
        s.fillSmoothCircle(20, 8, 3, btCol);
        // Small "B" diacritic: two tiny bumps on the right side
        s.fillSmoothCircle(23, 6, 1, btCol);
        s.fillSmoothCircle(23, 10, 1, btCol);
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

    if (useSprite) sprite.pushSprite(0, 0);
}

void renderClock(const display::StatusBar& status) {
    tft.fillScreen(COL_BG);

    // Large time — use LovyanGFX native font
    tft.setTextDatum(lgfx::middle_center);
    tft.setTextSize(5);
    tft.setTextColor(COL_FACE);

    // Get current time (placeholder — needs RTC or NTP)
    uint32_t sec = millis() / 1000;
    uint8_t h = (sec / 3600) % 24;
    uint8_t m = (sec / 60) % 60;
    char timeBuf[8];
    snprintf(timeBuf, sizeof(timeBuf), "%02d:%02d", h, m);
    tft.drawString(timeBuf, CX, CY - 20);

    // Date placeholder
    tft.setTextSize(2);
    tft.setTextColor(COL_DIM);
    tft.drawString("Aksabot", CX, CY + 30);
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

    // Icon
    s.setTextDatum(lgfx::middle_center);
    s.setTextSize(3);
    s.setTextColor(COL_WARM);
    s.drawString("!", CX, 40);

    // Reminder text — word-wrap at size 2
    s.setTextSize(2);
    s.setTextColor(COL_FACE);
    s.setTextDatum(lgfx::top_left);

    const int marginX = 10;
    const int maxW = LCD_WIDTH - marginX * 2;
    const int lineH = 22;
    int y = 75;

    // Simple word-wrap
    char buf[256];
    strncpy(buf, data.text, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';

    char line[64] = {};
    char* word = strtok(buf, " ");
    while (word) {
        char test[64];
        if (line[0] == '\0') {
            strncpy(test, word, sizeof(test) - 1);
        } else {
            snprintf(test, sizeof(test), "%s %s", line, word);
        }
        test[sizeof(test) - 1] = '\0';

        if (s.textWidth(test) > maxW && line[0] != '\0') {
            s.drawString(line, marginX, y);
            y += lineH;
            strncpy(line, word, sizeof(line) - 1);
        } else {
            strncpy(line, test, sizeof(line) - 1);
        }
        line[sizeof(line) - 1] = '\0';
        word = strtok(nullptr, " ");
    }
    if (line[0] != '\0') {
        s.drawString(line, marginX, y);
    }

    // Dismiss hint
    s.setTextSize(1);
    s.setTextColor(COL_DIM);
    s.setTextDatum(lgfx::middle_center);
    s.drawString("tap to dismiss", CX, LCD_HEIGHT - 20);
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
    tft.setTextDatum(lgfx::top_left);
    tft.setTextSize(2);

    int y = 20;
    const int lineH = 28;

    tft.setTextColor(COL_ACCENT);
    tft.drawString("System Status", 10, y); y += lineH + 10;

    tft.setTextColor(COL_FACE);
    tft.drawString(status.wifiConnected ? "WiFi: Connected" : "WiFi: Offline", 10, y);
    y += lineH;

    tft.drawString(status.wsConnected ? "Backend: Online" : "Backend: Offline", 10, y);
    y += lineH;

    const char* sigLabel = (status.wifiRssi > -50) ? "Excellent" : (status.wifiRssi > -60) ? "Good" :
                           (status.wifiRssi > -70) ? "Fair" : (status.wifiRssi > -80) ? "Weak" : "Poor";
    char rssBuf[32];
    snprintf(rssBuf, sizeof(rssBuf), "Signal: %s (%d)", sigLabel, status.wifiRssi);
    tft.drawString(rssBuf, 10, y); y += lineH;

    if (status.batteryPercent == 255) {
        tft.drawString("Power: USB", 10, y);
    } else {
        char batBuf[16];
        snprintf(batBuf, sizeof(batBuf), "Battery: %d%%", status.batteryPercent);
        tft.drawString(batBuf, 10, y);
    }
}

/// Draw transcript overlay into a target (sprite or tft).
void renderTranscriptOverlay(LGFX_Sprite& target, const char* text) {
    const int padX = 8;
    const int padY = 5;
    const int lineH = 14;
    const int maxLines = 3;
    const int maxCharsPerLine = 36;

    target.setFont(&fonts::Font2);
    target.setTextSize(1);
    target.setTextDatum(lgfx::top_left);

    // Word-wrap text into lines
    char lines[maxLines][42];
    int lineCount = 0;
    memset(lines, 0, sizeof(lines));

    const char* p = text;
    int col = 0;

    while (*p && lineCount < maxLines) {
        while (*p == ' ') p++;
        if (!*p) break;

        const char* wordStart = p;
        while (*p && *p != ' ') p++;
        int wordLen = p - wordStart;

        if (col + (col > 0 ? 1 : 0) + wordLen > maxCharsPerLine) {
            lineCount++;
            col = 0;
            if (lineCount >= maxLines) break;
        }

        if (col > 0) lines[lineCount][col++] = ' ';

        int copyLen = (col + wordLen < (int)sizeof(lines[0]) - 1) ? wordLen : ((int)sizeof(lines[0]) - 1 - col);
        memcpy(&lines[lineCount][col], wordStart, copyLen);
        col += copyLen;
        lines[lineCount][col] = '\0';
    }
    if (col > 0) lineCount++;

    int barH = padY * 2 + lineCount * lineH;
    int barY = LCD_HEIGHT - barH;

    target.fillRect(0, barY, LCD_WIDTH, barH, COL_STATUS_BG);

    target.setTextColor(COL_FACE);
    for (int i = 0; i < lineCount; i++) {
        target.drawString(lines[i], padX, barY + padY + i * lineH);
    }
}

void renderGlance(const display::GlanceData& data) {
    LGFX_Sprite& s = sprite.getBuffer() ? sprite : (LGFX_Sprite&)tft;
    bool useSprite = (sprite.getBuffer() != nullptr);

    if (useSprite) s.fillSprite(COL_BG);
    else           tft.fillScreen(COL_BG);

    // ── Large time ──
    s.setTextDatum(lgfx::middle_center);
    s.setFont(&fonts::Font0);
    s.setTextSize(6);
    s.setTextColor(COL_FACE);
    s.drawString(data.time, CX, 80);

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

    // Rate-limit rendering
    if ((nowMs - lastRenderMs) < RENDER_INTERVAL_MS) return;
    lastRenderMs = nowMs;

    // Advance face animation
    face::tick(nowMs);

    // Check auto-return timer
    if (autoReturnActive && nowMs >= autoReturnAtMs) {
        autoReturnActive = false;
        currentMode = previousMode;
    }

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
    }

}

void display::setMode(Mode mode) {
    if (mode == currentMode && !autoReturnActive) return;
    previousMode = currentMode;
    currentMode = mode;
    autoReturnActive = false;
    if (sleeping) wake();
}

display::Mode display::getMode() {
    return currentMode;
}

void display::setModeTemporary(Mode mode, uint16_t durationMs) {
    previousMode = currentMode;
    currentMode = mode;
    autoReturnActive = true;
    autoReturnAtMs = millis() + durationMs;
    if (sleeping) wake();
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

void display::setTranscriptText(const char* text) {
    strncpy(transcriptText, text, sizeof(transcriptText) - 1);
    transcriptText[sizeof(transcriptText) - 1] = '\0';
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
}

void display::showGlance() {
    if (!contextDataAvailable) return;
    glanceData = latestContext;
    setModeTemporary(Mode::GLANCE, 8000);
}

bool display::hasContextData() {
    return contextDataAvailable;
}
