#pragma once
#include <cstdint>

/// Boot screen — shown during setup() before the main face UI.
///
/// Sequence: splash → hardware check → provisioning prompt → connecting → ready.
/// Uses LovyanGFX display (must call display_hw init first, or call boot_screen::init()).
namespace boot_screen {

/// Initialize display for boot screen (calls tft.init if not already done).
void init();

/// Show splash screen: logo + firmware version.
void showSplash(const char* version);

/// Show hardware check progress. Call multiple times as each subsystem initializes.
/// status: 0=checking, 1=ok, 2=failed, 3=skipped
void showHardwareCheck(const char* component, uint8_t status);

/// Show provisioning prompt with AP name and password.
void showProvisioningPrompt(const char* apName, const char* apIp);

/// Update provisioning status (e.g., "Phone connected", "Receiving WiFi...").
void showProvisioningStatus(const char* status);

/// Show WiFi connecting progress.
void showConnecting(const char* ssid);

/// Show connection result.
void showConnected(const char* ip);
void showConnectionFailed(const char* reason);

/// Show "Ready!" and transition hint.
void showReady();

}  // namespace boot_screen
