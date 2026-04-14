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
