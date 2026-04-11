"""
PlatformIO pre-build script: copy patched ArduinoWebsockets files over the
library dependency copies. This survives `pio run -t clean` because the
script re-applies patches at every build.

Patches:
  - esp32_tcp.hpp: adds setInsecure() to SecuredEsp32TcpClient (ESP32 parity with ESP8266)
  - websockets_client.cpp: adds client->setInsecure() fallback when no CA cert for ESP32
"""
import shutil
import os

Import("env")

patches_dir = os.path.join(env.subst("$PROJECT_DIR"), "patches")
lib_dir = os.path.join(
    env.subst("$PROJECT_LIBDEPS_DIR"),
    env.subst("$PIOENV"),
    "ArduinoWebsockets",
    "src",
)

patches = [
    (
        os.path.join(patches_dir, "esp32_tcp.hpp"),
        os.path.join(lib_dir, "tiny_websockets", "network", "esp32", "esp32_tcp.hpp"),
    ),
    (
        os.path.join(patches_dir, "websockets_client.cpp"),
        os.path.join(lib_dir, "websockets_client.cpp"),
    ),
]

for src, dst in patches:
    if os.path.exists(src) and os.path.exists(os.path.dirname(dst)):
        shutil.copy2(src, dst)
        print(f"  [PATCH] {os.path.basename(src)} -> {dst}")
    else:
        print(f"  [PATCH] SKIP {os.path.basename(src)} (target dir missing — run pio pkg install first)")
