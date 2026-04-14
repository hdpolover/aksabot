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
        /* SURPRISED   */       { true,   82,  48,  0.00f, 0.00f, 0.00f, 0.50f, false,  0,   0 },
        /* SHOCKED     */       { true,   86,  52,  0.00f, 0.00f, 0.00f, 0.00f, false,  0,   0 },
        /* ANGRY       */       { true,   52,  28,  0.38f, 0.00f, 0.38f, 0.30f, false,-12,   0 },
        /* DISTURBED   */       { true,   68,  38,  0.00f, 0.00f, 0.00f, 1.00f, false,  0,   0 },
    },
};
