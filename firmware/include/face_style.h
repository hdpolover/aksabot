#pragma once
#include "face.h"
#include <cstdint>

/// Face style template system.
///
/// A FaceStyleDef is a data table that drives eye rendering for every expression.
/// Selecting a style at runtime immediately changes how all subsequent frames look.
///
/// Built-in presets (one .cpp file each, easy to add more):
///   face_style::ORBIT  — classic circle eyes with pupil/iris (original v1)
///   face_style::NOVA   — flat rounded-rectangle eyes (v2, modern/geometric)
///
/// To add a new face: create face_<name>.cpp, define a FaceStyleDef, add an
/// extern declaration below, and register it in face_style::fromName().

namespace face_style {

/// Per-expression eye drawing parameters.
/// Only the relevant fields are read depending on useRoundRect.
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
};

/// Unique style identifiers — stored in NVS as uint8_t.
enum class StyleId : uint8_t {
    ORBIT = 0,   ///< Classic circle eyes (v1)
    NOVA  = 1,   ///< Rounded rectangle eyes (v2)
};

/// A complete face style definition — one entry per expression, in enum order.
struct FaceStyleDef {
    const char* name;   ///< Lowercase key used in config:update ("orbit", "nova")
    StyleId     id;
    ExprEyeStyle eyes[static_cast<uint8_t>(face::Expression::COUNT)];
};

// ── Built-in presets ──────────────────────────────────────────────────────
// Definitions live in face_orbit.cpp and face_nova.cpp respectively.
// To add a new face: create face_<name>.cpp and add an extern here.

extern const FaceStyleDef ORBIT;
extern const FaceStyleDef NOVA;

/// Returns the preset matching name ("orbit" / "nova").
/// Falls back to NOVA for unknown names.
const FaceStyleDef* fromName(const char* name);

/// Returns the preset matching id.
/// Falls back to NOVA for unknown ids.
const FaceStyleDef* fromId(uint8_t id);

}  // namespace face_style
