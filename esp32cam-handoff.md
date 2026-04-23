# ESP32-CAM Setup Handoff

## Hardware
- Board: AI-Thinker ESP32-CAM-MB (built-in USB programmer)
- Chip: ESP32-D0WD-V3 rev 3.1 with PSRAM
- Camera: OV3660 (3MP)
- MAC: a4:f0:0f:74:39:c0
- Flash: 4MB
- Port: /dev/tty.usbserial-21240

## Firmware
- Tasmota 15.4.0 (release-webcam)
- Binary: tasmota32-webcam.factory.bin (saved at ~/tasmota32-webcam.factory.bin)
- Source: https://ota.tasmota.com/tasmota32/release/tasmota32-webcam.factory.bin

## Network
- WiFi: PT MIT
- IP: 192.168.10.23
- Hostname: tasmota-7439C0-6592

## Access URLs
- Web UI: http://192.168.10.23
- Live stream (MJPEG): http://192.168.10.23:81/stream

## Camera Status
- OV3660 initialized OK
- FPS: 28 (at default frame size)
- CamFail: 0

## How to Re-flash (if needed)
```bash
# esptool already installed via pip3
python3 -m esptool --port /dev/tty.usbserial-21240 --baud 460800 --chip esp32 \
  --before default-reset --after hard-reset \
  write-flash --flash-mode dio --flash-freq 80m --flash-size detect \
  0x0 ~/tasmota32-webcam.factory.bin
```

## Tasmota Template (AI-Thinker)
Run in Tasmota Console if device resets to default:
```
Backlog Template {"NAME":"ESP32-CAM","GPIO":[1,1,1,1,1,1,0,0,1,1,1,1,1,0,5088,5120,0,0,5184,5216,0,5280,0,5312,0,0,0,0,4736,160,5024,5056,5344,0,0,5376],"FLAG":0,"BASE":2}; Module 0
```

## FPS Tuning
Change frame size in Tasmota Console:
```
WebcamFrameSize 4
```
- 0 = QQVGA 160x120 (~25fps)
- 5 = VGA 640x480 (~10fps, default)
- 13 = UXGA 1600x1200 (~2fps)

## Next Step: Custom C++ Firmware
Tasmota works but has overhead. Custom ESP-IDF firmware can achieve:
- 30+ fps at VGA
- Lower latency
- Dual-core: Core 0 capture, Core 1 stream
- Custom processing (motion detect, RTSP, etc.)
- Stack: ESP-IDF + esp32-camera component (OV3660 supported)
- Effort: ~200 lines C for minimal MJPEG stream server
