#include "ble_manager.h"
#include "nvs_store.h"
#include "display.h"
#include "wifi_manager.h"
#include "state.h"
#include "presence_detector.h"
#include <NimBLEDevice.h>
#include <Arduino.h>
#include <freertos/semphr.h>

// ── GATT UUIDs (match Flutter app's ble_constants.dart) ──

// Services
#define UUID_WIFI_SVC      "0000ffe0-0000-1000-8000-00805f9b34fb"
#define UUID_AUTH_SVC      "0000ffe1-0000-1000-8000-00805f9b34fb"
#define UUID_CTRL_SVC      "0000ffe2-0000-1000-8000-00805f9b34fb"
#define UUID_STATUS_SVC    "0000ffe3-0000-1000-8000-00805f9b34fb"
#define UUID_PRESENCE_SVC  "0000ffe4-0000-1000-8000-00805f9b34fb"

// WiFi characteristics
#define UUID_WIFI_SSID     "0000ffe0-0001-1000-8000-00805f9b34fb"
#define UUID_WIFI_PASSWORD "0000ffe0-0002-1000-8000-00805f9b34fb"
#define UUID_WIFI_STATUS   "0000ffe0-0003-1000-8000-00805f9b34fb"

// Auth characteristics
#define UUID_DEVICE_TOKEN  "0000ffe1-0001-1000-8000-00805f9b34fb"
#define UUID_AUTH_STATUS   "0000ffe1-0002-1000-8000-00805f9b34fb"

// Control characteristics
#define UUID_VOLUME        "0000ffe2-0001-1000-8000-00805f9b34fb"
#define UUID_BRIGHTNESS    "0000ffe2-0002-1000-8000-00805f9b34fb"

// Status characteristics
#define UUID_BATTERY       "0000ffe3-0001-1000-8000-00805f9b34fb"
#define UUID_WIFI_RSSI_C   "0000ffe3-0002-1000-8000-00805f9b34fb"
#define UUID_UPTIME        "0000ffe3-0003-1000-8000-00805f9b34fb"

// ── Internal state ──────────────────────────────────────

static NimBLEServer* pServer = nullptr;

// WiFi service chars
static NimBLECharacteristic* pWifiSsid     = nullptr;
static NimBLECharacteristic* pWifiPassword = nullptr;
static NimBLECharacteristic* pWifiStatus   = nullptr;

// Auth service chars
static NimBLECharacteristic* pDeviceToken  = nullptr;
static NimBLECharacteristic* pAuthStatus   = nullptr;

// Control service chars
static NimBLECharacteristic* pVolume       = nullptr;
static NimBLECharacteristic* pBrightness   = nullptr;

// Status service chars
static NimBLECharacteristic* pBattery      = nullptr;
static NimBLECharacteristic* pWifiRssi     = nullptr;
static NimBLECharacteristic* pUptime       = nullptr;

static SemaphoreHandle_t provisionedSem = nullptr;
static volatile bool clientConnected = false;
static volatile bool provisioned = false;
static bool bleInitialized = false;

// Pending credentials (written by BLE callbacks)
static char pendingSsid[64] = {};
static char pendingPass[128] = {};

// ── WiFi status watch task ──────────────────────────────

static void wifiStatusWatchTask(void*) {
    uint32_t start = millis();
    while ((millis() - start) < 20000) {
        if (appState.wifiConnected) {
            ble_manager::notifyWifiStatus(2);  // connected
            Serial.println("[BLE] WiFi connected — notified client");
            vTaskDelete(nullptr);
            return;
        }
        vTaskDelay(pdMS_TO_TICKS(500));
    }
    ble_manager::notifyWifiStatus(3);  // failed
    Serial.println("[BLE] WiFi connect timeout — notified client");
    vTaskDelete(nullptr);
}

// ── Server callbacks ────────────────────────────────────

class ServerCallbacks : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* server, NimBLEConnInfo& connInfo) override {
        clientConnected = true;
        Serial.println("[BLE] Client connected");
    }

    void onDisconnect(NimBLEServer* server, NimBLEConnInfo& connInfo, int reason) override {
        clientConnected = false;
        Serial.println("[BLE] Client disconnected");
        // Restart advertising so the app can reconnect
        NimBLEDevice::startAdvertising();
    }
};

// ── WiFi SSID write callback ────────────────────────────

class SsidCallback : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pChar, NimBLEConnInfo& connInfo) override {
        std::string value = pChar->getValue();
        if (value.length() > 0 && value.length() < sizeof(pendingSsid)) {
            strncpy(pendingSsid, value.c_str(), sizeof(pendingSsid) - 1);
            pendingSsid[value.length()] = '\0';
            nvs_store::setWifiSsid(pendingSsid);
            Serial.printf("[BLE] SSID received: %s\n", pendingSsid);
        }
    }
};

// ── WiFi Password write callback ────────────────────────

class PasswordCallback : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pChar, NimBLEConnInfo& connInfo) override {
        std::string value = pChar->getValue();
        if (value.length() > 0 && value.length() < sizeof(pendingPass)) {
            strncpy(pendingPass, value.c_str(), sizeof(pendingPass) - 1);
            pendingPass[value.length()] = '\0';
            nvs_store::setWifiPassword(pendingPass);
            Serial.printf("[BLE] Password received (%d chars)\n", value.length());

            // Both credentials now set — signal main loop to handle WiFi.
            // Don't start WiFi here: wifi_manager::init() needs to run first
            // (registers event handler, sets STA mode) and calling reconnect()
            // from this callback causes a double-init that delays connection.
            if (strlen(pendingSsid) > 0) {
                ble_manager::notifyWifiStatus(1);  // connecting

                provisioned = true;
                if (provisionedSem) {
                    xSemaphoreGive(provisionedSem);
                }
            }
        }
    }
};

// ── Device Token write callback ─────────────────────────

class TokenCallback : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pChar, NimBLEConnInfo& connInfo) override {
        std::string value = pChar->getValue();
        if (value.length() == 0) return;

        // The app sends "token\nbackendUrl" — parse both.
        size_t sep = value.find('\n');
        if (sep != std::string::npos) {
            std::string token = value.substr(0, sep);
            std::string url   = value.substr(sep + 1);
            nvs_store::setDeviceToken(token.c_str());
            if (!url.empty()) {
                nvs_store::setBackendUrl(url.c_str());
                Serial.printf("[BLE] Backend URL saved: %s\n", url.c_str());
            }
            Serial.printf("[BLE] Device token stored (%d chars)\n", token.length());
        } else {
            // Legacy: plain token without URL
            nvs_store::setDeviceToken(value.c_str());
            Serial.printf("[BLE] Device token stored (%d chars)\n", value.length());
        }
        ble_manager::notifyAuthStatus(1);  // token stored
    }
};

// ── Volume write callback ───────────────────────────────

class VolumeCallback : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pChar, NimBLEConnInfo& connInfo) override {
        uint8_t vol = pChar->getValue<uint8_t>();
        nvs_store::setVolume(vol);
        Serial.printf("[BLE] Volume set: %d\n", vol);
    }

    void onRead(NimBLECharacteristic* pChar, NimBLEConnInfo& connInfo) override {
        pChar->setValue(nvs_store::getVolume());
    }
};

// ── Brightness write callback ───────────────────────────

class BrightnessCallback : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pChar, NimBLEConnInfo& connInfo) override {
        uint8_t brt = pChar->getValue<uint8_t>();
        nvs_store::setBrightness(brt);
        display::fadeBrightness(brt, 200);
        Serial.printf("[BLE] Brightness set: %d\n", brt);
    }

    void onRead(NimBLECharacteristic* pChar, NimBLEConnInfo& connInfo) override {
        pChar->setValue(nvs_store::getBrightness());
    }
};

// ── Presence scan callbacks ─────────────────────────────
//
// The phone advertises every ~250ms (Android balanced) or ~100ms (iOS).
// Over a 5-second scan window that's 20-50 onResult callbacks. Feeding the
// state machine on every callback causes rapid flapping. Instead:
//   onResult  — accumulate RSSI readings for this cycle (no state change)
//   onScanEnd — feed ONE averaged reading to the state machine, then restart
//
// This guarantees exactly one state transition evaluation per scan cycle.

static volatile bool    presenceFoundThisCycle  = false;
static volatile int32_t presenceCycleRssiSum    = 0;
static volatile int16_t presenceCycleRssiCount  = 0;
static volatile int16_t presenceCycleTotalSeen  = 0;  // all BLE devices, for diagnostics
// Set by onScanEnd (NimBLE host task context).
// Consumed by tickPresenceScan (main loop context).
// Never call scan->start() from within onScanEnd — it deadlocks the nimble_host
// task and triggers the task watchdog.
static volatile bool    presenceScanEndPending  = false;
// Monotonically increasing counter bumped on every startPresenceScan() /
// stopPresenceScan(). onScanEnd captures the generation at scan-start time;
// tickPresenceScan discards results whose generation doesn't match the current
// one.  This prevents stale onScanEnd callbacks (from a stopped scan) from
// triggering spurious configureAndStartScan() calls when rapid stop/start
// sequences arrive via config:update.
static volatile uint32_t presenceScanGeneration = 0;
static volatile uint32_t pendingScanGeneration  = 0;

static bool presenceScanActive = false;
static bool presenceScanPaused = false;

static void resetCycleCounters() {
    presenceFoundThisCycle  = false;
    presenceCycleRssiSum    = 0;
    presenceCycleRssiCount  = 0;
    presenceCycleTotalSeen  = 0;
}

class PresenceScanCallbacks : public NimBLEScanCallbacks {
    // Called for every BLE advertisement received during the scan window.
    // Only accumulate RSSI — never touch the state machine or call scan->start().
    void onResult(const NimBLEAdvertisedDevice* device) override {
        presenceCycleTotalSeen++;

        // Debug: dump every device seen so we can verify what the phone advertises.
        // Logs address, RSSI, service UUID presence, and raw manufacturer data bytes.
        {
            bool hasSvc = device->isAdvertisingService(NimBLEUUID(UUID_PRESENCE_SVC));
            if (device->haveManufacturerData()) {
                const std::string& m = device->getManufacturerData();
                // Print up to 6 bytes of manufacturer data as hex
                int printLen = m.size() < 6 ? m.size() : 6;
                char hex[20] = {};
                for (int i = 0; i < printLen; i++) {
                    snprintf(hex + i * 3, 4, "%02X ", (uint8_t)m[i]);
                }
                Serial.printf("[BLE] Device rssi=%d svcMatch=%d mfrLen=%d mfr=[%s]\n",
                              device->getRSSI(), hasSvc, (int)m.size(), hex);
            } else {
                Serial.printf("[BLE] Device rssi=%d svcMatch=%d noMfr\n",
                              device->getRSSI(), hasSvc);
            }
        }

        bool isPresenceDevice = false;

        // Primary check: service UUID (works on iOS and some Android builds)
        if (device->isAdvertisingService(NimBLEUUID(UUID_PRESENCE_SVC))) {
            isPresenceDevice = true;
        }

        // Fallback: manufacturer data (manufacturer ID 0xFFFF + magic 0xAB 0xCF).
        // Android's flutter_ble_peripheral often omits the service UUID from the
        // advertisement payload. Manufacturer data is always present and reliable
        // across all Android OEMs and SDK versions.
        if (!isPresenceDevice && device->haveManufacturerData()) {
            const std::string& mfr = device->getManufacturerData();
            // BLE manufacturer data layout: [ID_LO, ID_HI, data...]
            // ID 0xFFFF = little-endian bytes 0xFF 0xFF, magic = 0xAB 0xCF
            if (mfr.size() >= 4 &&
                (uint8_t)mfr[0] == 0xFF && (uint8_t)mfr[1] == 0xFF &&
                (uint8_t)mfr[2] == 0xAB && (uint8_t)mfr[3] == 0xCF) {
                isPresenceDevice = true;
            }
        }

        if (isPresenceDevice) {
            int8_t rssi = device->getRSSI();
            presenceCycleRssiSum   += rssi;
            presenceCycleRssiCount += 1;
            if (!presenceFoundThisCycle) {
                Serial.printf("[BLE] Presence device found, RSSI=%d\n", rssi);
            }
            presenceFoundThisCycle  = true;
        }
    }

    // Called exactly once when the scan duration elapses (or stop() is called).
    // IMPORTANT: Do NOT call scan->start() here — this runs inside the nimble_host
    // FreeRTOS task. Calling start() from within a NimBLE callback causes a
    // deadlock that fires the task watchdog. Capture the generation so
    // tickPresenceScan can discard stale results from rapid stop/start sequences.
    void onScanEnd(const NimBLEScanResults& /*results*/, int /*reason*/) override {
        pendingScanGeneration  = presenceScanGeneration;
        presenceScanEndPending = true;
    }
};

// ── Public API ──────────────────────────────────────────

void ble_manager::init() {
    provisionedSem = xSemaphoreCreateBinary();

    NimBLEDevice::init("Aksabot");
    NimBLEDevice::setMTU(185);
    NimBLEDevice::setPower(6);  // +6dBm for good range
    bleInitialized = true;

    pServer = NimBLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks());

    // ── WiFi Service (0xFFE0) ───────────────────────────
    NimBLEService* wifiSvc = pServer->createService(UUID_WIFI_SVC);

    pWifiSsid = wifiSvc->createCharacteristic(
        UUID_WIFI_SSID,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE
    );
    pWifiSsid->setCallbacks(new SsidCallback());

    pWifiPassword = wifiSvc->createCharacteristic(
        UUID_WIFI_PASSWORD,
        NIMBLE_PROPERTY::WRITE
    );
    pWifiPassword->setCallbacks(new PasswordCallback());

    pWifiStatus = wifiSvc->createCharacteristic(
        UUID_WIFI_STATUS,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );
    uint8_t initialWifiStatus = 0;
    pWifiStatus->setValue(&initialWifiStatus, 1);

    // Services auto-start with server in NimBLE v2

    // ── Auth Service (0xFFE1) ───────────────────────────
    NimBLEService* authSvc = pServer->createService(UUID_AUTH_SVC);

    pDeviceToken = authSvc->createCharacteristic(
        UUID_DEVICE_TOKEN,
        NIMBLE_PROPERTY::WRITE
    );
    pDeviceToken->setCallbacks(new TokenCallback());

    pAuthStatus = authSvc->createCharacteristic(
        UUID_AUTH_STATUS,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );
    uint8_t initialAuthStatus = nvs_store::hasDeviceToken() ? 1 : 0;
    pAuthStatus->setValue(&initialAuthStatus, 1);


    // ── Control Service (0xFFE2) ────────────────────────
    NimBLEService* ctrlSvc = pServer->createService(UUID_CTRL_SVC);

    pVolume = ctrlSvc->createCharacteristic(
        UUID_VOLUME,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE
    );
    pVolume->setCallbacks(new VolumeCallback());
    uint8_t vol = nvs_store::getVolume();
    pVolume->setValue(&vol, 1);

    pBrightness = ctrlSvc->createCharacteristic(
        UUID_BRIGHTNESS,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE
    );
    pBrightness->setCallbacks(new BrightnessCallback());
    uint8_t brt = nvs_store::getBrightness();
    pBrightness->setValue(&brt, 1);


    // ── Status Service (0xFFE3) ─────────────────────────
    NimBLEService* statusSvc = pServer->createService(UUID_STATUS_SVC);

    pBattery = statusSvc->createCharacteristic(
        UUID_BATTERY,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );
    uint8_t bat = 255;  // USB-powered
    pBattery->setValue(&bat, 1);

    pWifiRssi = statusSvc->createCharacteristic(
        UUID_WIFI_RSSI_C,
        NIMBLE_PROPERTY::READ
    );
    int8_t rssi = 0;
    pWifiRssi->setValue((uint8_t*)&rssi, 1);

    pUptime = statusSvc->createCharacteristic(
        UUID_UPTIME,
        NIMBLE_PROPERTY::READ
    );
    uint32_t up = 0;
    pUptime->setValue((uint8_t*)&up, 4);


    // ── Start advertising ───────────────────────────────
    // Use 16-bit short UUID form (4 bytes) instead of 128-bit (17 bytes).
    // The full 128-bit UUID overflows the 31-byte advertisement packet when
    // combined with the device name, causing NimBLE to spill it into the scan
    // response. iOS CoreBluetooth only reads the primary packet for service
    // UUID filtering, so it never finds the device. Short UUIDs always fit.
    NimBLEAdvertising* pAdvertising = NimBLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(NimBLEUUID((uint16_t)0xFFE0));
    pAdvertising->setName("Aksabot");
    pAdvertising->enableScanResponse(true);
    pAdvertising->setPreferredParams(0x06, 0x12);
    pAdvertising->start();

    Serial.println("[BLE] GATT server started, advertising 0xFFE0");
}

void ble_manager::initScanOnly() {
    if (bleInitialized) return;  // Already inited (e.g., from provisioning)

    NimBLEDevice::init("Aksabot");
    NimBLEDevice::setPower(6);
    bleInitialized = true;

    Serial.println("[BLE] Initialized (scan-only mode)");
}

bool ble_manager::isInitialized() {
    return bleInitialized;
}

bool ble_manager::waitForProvisioning(uint32_t timeoutMs) {
    TickType_t ticks = (timeoutMs == 0) ? portMAX_DELAY : pdMS_TO_TICKS(timeoutMs);

    Serial.println("[BLE] Waiting for WiFi credentials via BLE...");
    bool got = (xSemaphoreTake(provisionedSem, ticks) == pdTRUE);

    if (got) {
        Serial.printf("[BLE] Provisioned! SSID=%s\n", pendingSsid);
    } else {
        Serial.println("[BLE] Provisioning timeout");
    }
    return got;
}

bool ble_manager::isProvisioned() {
    return provisioned;
}

void ble_manager::startAdvertising() {
    NimBLEDevice::startAdvertising();
    Serial.println("[BLE] Advertising started");
}

void ble_manager::stopAdvertising() {
    NimBLEDevice::stopAdvertising();
    Serial.println("[BLE] Advertising stopped");
}

void ble_manager::notifyWifiStatus(uint8_t status) {
    if (pWifiStatus) {
        pWifiStatus->setValue(&status, 1);
        if (clientConnected) {
            pWifiStatus->notify();
        }
    }
}

void ble_manager::notifyWifiConnectedWithIp(const char* ip) {
    if (!pWifiStatus) return;
    // Pack status + IP into one notification: [2, '1','9','2','.','1','6','8',...]
    size_t ipLen = strlen(ip);
    uint8_t buf[32];
    buf[0] = 2;  // connected
    if (ipLen > sizeof(buf) - 1) ipLen = sizeof(buf) - 1;
    memcpy(buf + 1, ip, ipLen);
    pWifiStatus->setValue(buf, 1 + ipLen);
    if (clientConnected) {
        pWifiStatus->notify();
    }
}

void ble_manager::notifyAuthStatus(uint8_t status) {
    if (pAuthStatus) {
        pAuthStatus->setValue(&status, 1);
        if (clientConnected) {
            pAuthStatus->notify();
        }
    }
}

static PresenceScanCallbacks presenceScanCb;

static void configureAndStartScan() {
    NimBLEScan* pScan = NimBLEDevice::getScan();
    // Active scan, ~37.5% duty cycle: 80/30 = 37.5% air time.
    // Active scanning sends scan requests and receives scan responses, which is
    // necessary for Android — connectable advertisements put service UUIDs in
    // the scan response (not the primary advertisement packet).
    // iOS background advertising: iOS sends unsolicited scan responses even in
    // background mode, so active scanning is also beneficial for iOS.
    pScan->setActiveScan(true);
    pScan->setInterval(80);    //  80 * 0.625ms =  50ms scan interval
    pScan->setWindow(30);      //  30 * 0.625ms = 18.75ms active window → 37.5%
    pScan->setMaxResults(0);   // Don't buffer results in heap — use callbacks only
    resetCycleCounters();
    uint32_t scanSec = presence_detector::getRecommendedScanIntervalMs() / 1000;
    if (scanSec < 1) scanSec = 1;
    pScan->start(scanSec, false);
}

void ble_manager::startPresenceScan() {
    NimBLEScan* pScan = NimBLEDevice::getScan();
    pScan->setScanCallbacks(&presenceScanCb, false);
    presenceScanActive = true;
    presenceScanPaused = false;
    // Bump generation so any in-flight onScanEnd from a prior stop() is ignored.
    presenceScanGeneration++;
    presenceScanEndPending = false;
    configureAndStartScan();
    Serial.println("[BLE] Presence scanning started");
}

void ble_manager::stopPresenceScan() {
    presenceScanActive = false;
    presenceScanPaused = false;
    // Bump generation before stop() so the asynchronous onScanEnd that fires
    // later carries a stale generation and will be ignored by tickPresenceScan.
    presenceScanGeneration++;
    presenceScanEndPending = false;
    resetCycleCounters();
    NimBLEDevice::getScan()->stop();
    Serial.println("[BLE] Presence scanning stopped");
}

void ble_manager::pausePresenceScan() {
    if (!presenceScanActive || presenceScanPaused) return;
    presenceScanPaused     = true;
    presenceScanEndPending = false;   // discard result from interrupted scan cycle
    resetCycleCounters();
    NimBLEDevice::getScan()->stop();
    Serial.println("[BLE] Presence scan paused");
}

void ble_manager::resumePresenceScan() {
    if (!presenceScanActive || !presenceScanPaused) return;
    presenceScanPaused = false;
    configureAndStartScan();
    Serial.println("[BLE] Presence scan resumed");
}

// Called from main loop (safe context — not inside any NimBLE callback).
// Processes the scan-end flag set by onScanEnd and restarts the next cycle.
// Also acts as a watchdog: if the scan died without firing onScanEnd, restart it.
void ble_manager::tickPresenceScan(uint32_t nowMs) {
    if (!presenceScanActive || presenceScanPaused) return;

    if (presenceScanEndPending) {
        presenceScanEndPending = false;

        // Discard results from a scan that was stopped before the current session.
        // This happens when stopPresenceScan() + startPresenceScan() fire in rapid
        // succession: the old onScanEnd fires AFTER the new scan has already started.
        if (pendingScanGeneration != presenceScanGeneration) {
            // Stale result — just let the watchdog below restart if needed.
        } else {
            // Always log cycle summary — helps diagnose why phone isn't detected.
            if (presenceFoundThisCycle && presenceCycleRssiCount > 0) {
                // Phone seen this cycle — feed the averaged RSSI into the state machine.
                // This also updates lastScanHitMs, which resets the missing-timeout clock.
                int8_t avgRssi = (int8_t)(presenceCycleRssiSum / presenceCycleRssiCount);
                Serial.printf("[BLE] Presence cycle: %d seen, PHONE FOUND rssi=%d\n",
                              (int)presenceCycleTotalSeen, avgRssi);
                presence_detector::feedRssi(avgRssi);
            } else {
                // Print current state so it's clear what the detector thinks right now.
                PresenceState st = presence_detector::getState();
                const char* stStr =
                    st == PresenceState::PRESENT  ? "PRESENT"  :
                    st == PresenceState::LEAVING  ? "LEAVING"  :
                    st == PresenceState::AWAY     ? "AWAY"     : "UNKNOWN";
                Serial.printf("[BLE] Presence cycle: %d seen, phone NOT found — state=%s\n",
                              (int)presenceCycleTotalSeen, stStr);
            }
            // Phone not seen this cycle — do nothing here. Departure is handled by a
            // time-based timeout in presence_detector::tick(): if lastScanHitMs hasn't
            // been updated for missingTimeoutSec seconds, tick() starts LEAVING.
            // Per-cycle miss counts are unreliable because iOS/Android background
            // advertising can pause for several seconds even when user is at desk.

            resetCycleCounters();
            configureAndStartScan();
            return;
        }
    }

    // Watchdog: scan may have died without firing onScanEnd (NimBLE internal error).
    // Don't feed a miss — the cycle data is incomplete, just restart cleanly.
    if (!NimBLEDevice::getScan()->isScanning()) {
        resetCycleCounters();
        configureAndStartScan();
    }
}

bool ble_manager::isClientConnected() {
    return clientConnected;
}

void ble_manager::updateStatus(uint8_t batteryPercent, int8_t wifiRssiVal, uint32_t uptimeSeconds) {
    if (pBattery) pBattery->setValue(&batteryPercent, 1);
    if (pWifiRssi) pWifiRssi->setValue((uint8_t*)&wifiRssiVal, 1);
    if (pUptime) pUptime->setValue((uint8_t*)&uptimeSeconds, 4);
}
