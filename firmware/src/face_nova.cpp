#include "face_style.h"

// ── NOVA — Rounded rectangle eyes (v2) ───────────────────────────────────────
//
// Modern "screen character" style: flat filled rounded-rect eyes with no pupil.
// The whole rectangle shifts for gaze drift instead of moving a pupil inside.
// Bottom-lid squint is audio-reactive on expressive expressions (HAPPY, SPEAKING).
//
// Eye dimensions were chosen for the 240×320 ILI9341V display with EYE_SPACE=48.
// Adjust eyeW/eyeH per expression to tune the look on hardware.
//
// squintBase   — constant bottom-lid rise (0.0 = flat, 1.0 = fully closed)
// squintAmpScale — squint += mouthAmp × scale (audio-reactive lid)
// squintMax    — total squint cap (0.0 = uncapped)
// driftDamp    — gaze drift multiplier (1.0 = full, 0.0 = locked forward)

const face_style::FaceStyleDef face_style::NOVA = {
    /* name */ "nova",
    /* id   */ face_style::StyleId::NOVA,
    /* eyes */ {
        //                        useRR    W    H   sqBase sqAmp  sqMax  drift  brows
        /* IDLE        */       { true,   68,  38,  0.00f, 0.00f, 0.00f, 1.00f, false },
        /* LISTENING   */       { true,   74,  38,  0.00f, 0.00f, 0.00f, 1.00f, false },
        /* THINKING    */       { true,   60,  30,  0.15f, 0.00f, 0.15f, 1.00f, false },
        /* SPEAKING    */       { true,   68,  38,  0.00f, 0.30f, 0.30f, 0.25f, false },
        /* CONFUSED    */       { true,   68,  38,  0.00f, 0.00f, 0.00f, 1.00f, false },
        /* SLEEPING    */       { true,    0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false },  // special path — values unused
        /* OFFLINE     */       { true,    0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false },  // special path — values unused
        /* ENCOURAGING */       { true,   76,  40,  0.10f, 0.00f, 0.10f, 0.50f, true  },
        /* CALM        */       { true,   64,  36,  0.08f, 0.00f, 0.08f, 0.80f, false },
        /* FOCUSED     */       { true,   60,  34,  0.25f, 0.00f, 0.25f, 0.30f, false },
        /* HAPPY       */       { true,   72,  38,  0.15f, 0.65f, 0.75f, 0.00f, true  },
        /* SAD         */       { true,   64,  36,  0.00f, 0.00f, 0.00f, 0.80f, false },
        /* SHRUG       */       { true,   68,  38,  0.00f, 0.00f, 0.00f, 0.80f, true  },
        /* SURPRISED   */       { true,   80,  44,  0.00f, 0.00f, 0.00f, 0.50f, true  },
        /* SHOCKED     */       { true,   84,  46,  0.00f, 0.00f, 0.00f, 0.00f, false },
        /* ANGRY       */       { true,   52,  28,  0.35f, 0.00f, 0.35f, 0.30f, true  },
        /* DISTURBED   */       { true,   68,  38,  0.00f, 0.00f, 0.00f, 1.00f, false },
    },
};
