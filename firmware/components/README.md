# ESP-IDF Components

## libopus

The Opus codec library needs to be added here as an ESP-IDF component.

### Setup

```bash
cd components
git clone https://github.com/pschatzmann/arduino-libopus.git opus
```

This is a PlatformIO-compatible port of libopus that compiles for ESP32.

### Alternative: ESP-IDF native component

If using ESP-IDF framework (not Arduino), use:
```bash
cd components
git clone https://github.com/nicholasgasior/esp-opus.git opus
```
