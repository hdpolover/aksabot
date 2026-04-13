#include "face_style.h"

// ── ORBIT — Classic circle eyes (v1) ─────────────────────────────────────────
//
// Original procedural style: white filled circles with a black pupil that drifts
// inside the iris. Organic, cartoon-like feel.
//
// useRoundRect = false for every expression — the renderer uses the EYES[] table
// in display.cpp for the per-expression circle dimensions. The only field that
// matters in this preset is hasBrows, which mirrors what EYES[] declared.

const face_style::FaceStyleDef face_style::ORBIT = {
    /* name */ "orbit",
    /* id   */ face_style::StyleId::ORBIT,
    /* eyes */ {
        //                        useRR   W    H   sqBase sqAmp sqMax  drift  brows
        /* IDLE        */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false },
        /* LISTENING   */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false },
        /* THINKING    */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false },
        /* SPEAKING    */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false },
        /* CONFUSED    */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false },
        /* SLEEPING    */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false },
        /* OFFLINE     */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false },
        /* ENCOURAGING */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, true  },
        /* CALM        */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false },
        /* FOCUSED     */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false },
        /* HAPPY       */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, true  },
        /* SAD         */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false },
        /* SHRUG       */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, true  },
        /* SURPRISED   */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, true  },
        /* SHOCKED     */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false },
        /* ANGRY       */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, true  },
        /* DISTURBED   */       { false,  0,   0,  0.00f, 0.00f, 0.00f, 0.00f, false },
    },
};
