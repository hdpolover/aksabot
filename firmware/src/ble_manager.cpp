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

            // Both credentials now set — trigger WiFi connect
            if (strlen(pendingSsid) > 0) {
                ble_manager::notifyWifiStatus(1);  // connecting
                wifi_manager::reconnect(pendingSsid, pendingPass);

                // Signal provisioning complete
                provisioned = true;
                if (provisionedSem) {
                    xSemaphoreGive(provisionedSem);
                }

                // Spawn task to watch WiFi connect and notify status
                xTaskCreate(wifiStatusWatchTask, "ble_wifi", 2048, nullptr, 2, nullptr);
            }
        }
    }
};

// ── Device Token write callback ─────────────────────────

class TokenCallback : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pChar, NimBLEConnInfo& connInfo) override {
        std::string value = pChar->getValue();
        if (value.length() > 0) {
            nvs_store::setDeviceToken(value.c_str());
            ble_manager::notifyAuthStatus(1);  // token stored
            Serial.printf("[BLE] Device token stored (%d chars)\n", value.length());
        }
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

static volatile bool presenceFoundThisCycle = false;

class PresenceScanCallbacks : public NimBLEScanCallbacks {
    void onResult(const NimBLEAdvertisedDevice* device) override {
        if (device->isAdvertisingService(NimBLEUUID(UUID_PRESENCE_SVC))) {
            presence_detector::feedRssi(device->getRSSI());
            presenceFoundThisCycle = true;
        }
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
    NimBLEAdvertising* pAdvertising = NimBLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(UUID_WIFI_SVC);
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

void ble_manager::notifyAuthStatus(uint8_t status) {
    if (pAuthStatus) {
        pAuthStatus->setValue(&status, 1);
        if (clientConnected) {
            pAuthStatus->notify();
        }
    }
}

static PresenceScanCallbacks presenceScanCb;
static bool presenceScanActive = false;

void ble_manager::startPresenceScan() {
    NimBLEScan* pScan = NimBLEDevice::getScan();
    pScan->setScanCallbacks(&presenceScanCb, false);
    pScan->setActiveScan(false);
    pScan->setInterval(100);
    pScan->setWindow(50);
    presenceScanActive = true;

    uint32_t scanSec = presence_detector::getRecommendedScanIntervalMs() / 1000;
    if (scanSec < 1) scanSec = 1;
    presenceFoundThisCycle = false;
    pScan->start(scanSec, false);  // non-blocking, auto-stops after scanSec
    Serial.println("[BLE] Presence scanning started");
}

void ble_manager::stopPresenceScan() {
    presenceScanActive = false;
    NimBLEScan* pScan = NimBLEDevice::getScan();
    pScan->stop();
    Serial.println("[BLE] Presence scanning stopped");
}

// Called from loop() to restart scans after each cycle completes
static uint32_t lastScanStartMs = 0;

void ble_manager::tickPresenceScan(uint32_t nowMs) {
    if (!presenceScanActive) return;

    NimBLEScan* pScan = NimBLEDevice::getScan();
    if (!pScan->isScanning()) {
        // Previous scan ended — process results
        if (!presenceFoundThisCycle) {
            presence_detector::feedMiss();
        }

        // Restart scan
        uint32_t scanSec = presence_detector::getRecommendedScanIntervalMs() / 1000;
        if (scanSec < 1) scanSec = 1;
        presenceFoundThisCycle = false;
        pScan->start(scanSec, false);
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
