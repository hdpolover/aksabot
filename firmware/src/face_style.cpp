#include "face_style.h"
#include <cstring>

const face_style::FaceStyleDef* face_style::fromName(const char* name) {
    if (name == nullptr) return &NOVA;
    if (strcmp(name, "orbit") == 0) return &ORBIT;
    if (strcmp(name, "nova")  == 0) return &NOVA;
    return &NOVA;  // default
}

const face_style::FaceStyleDef* face_style::fromId(uint8_t id) {
    switch (static_cast<StyleId>(id)) {
        case StyleId::ORBIT: return &ORBIT;
        case StyleId::NOVA:  return &NOVA;
        default:             return &NOVA;
    }
}
