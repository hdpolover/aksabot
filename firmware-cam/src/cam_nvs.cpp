#include "cam_nvs.h"
#include "credentials.h"
#include <Preferences.h>

static Preferences prefs;

// Buffers filled once during init()
static char _ssid[64]    = WIFI_SSID;
static char _pass[64]    = WIFI_PASSWORD;
static char _host[128]   = BACKEND_HOST;
static uint16_t _port    = BACKEND_PORT;
static char _token[64]   = DEVICE_TOKEN;

namespace cam_nvs {

void init() {
    if (!prefs.begin("aksabot", true)) { // read-only
        Serial.println("[NVS] Namespace not found — using credentials.h defaults");
        return;
    }

    // WiFi
    if (prefs.isKey("wifi_ssid")) prefs.getString("wifi_ssid", _ssid, sizeof(_ssid));
    if (prefs.isKey("wifi_pass")) prefs.getString("wifi_pass", _pass, sizeof(_pass));

    // Device token
    if (prefs.isKey("dev_token")) prefs.getString("dev_token", _token, sizeof(_token));

    // Backend URL: parse wss://host/path or ws://host:port/path
    if (prefs.isKey("backend_url")) {
        char url[256] = {};
        prefs.getString("backend_url", url, sizeof(url));

        bool isSecure = strncmp(url, "wss://", 6) == 0;
        const char* start = url + (isSecure ? 6 : 5); // skip wss:// or ws://

        // Find end of host (either '/' or ':')
        const char* slash = strchr(start, '/');
        const char* colon = strchr(start, ':');

        if (colon && (!slash || colon < slash)) {
            // ws://host:port/path
            size_t hostLen = colon - start;
            if (hostLen < sizeof(_host)) {
                strncpy(_host, start, hostLen);
                _host[hostLen] = '\0';
            }
            _port = (uint16_t)atoi(colon + 1);
        } else {
            // wss://host/path (no explicit port)
            size_t hostLen = slash ? (size_t)(slash - start) : strlen(start);
            if (hostLen < sizeof(_host)) {
                strncpy(_host, start, hostLen);
                _host[hostLen] = '\0';
            }
            _port = isSecure ? 443 : 80;
        }
    }

    prefs.end();

    Serial.printf("[NVS] host=%s port=%d ssid=%s token=%.8s...\n",
        _host, _port, _ssid, _token);
}

const char* wifiSsid()   { return _ssid;  }
const char* wifiPass()   { return _pass;  }
const char* backendHost(){ return _host;  }
uint16_t    backendPort(){ return _port;  }
const char* deviceToken(){ return _token; }

} // namespace cam_nvs
