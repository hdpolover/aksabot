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

/// Show splash screen while polling BOOT button (GPIO 0).
/// Displays "Press BOOT for BIOS" hint. If BOOT is pressed during
/// the splash, shows confirmation and returns early (caller checks GPIO 0).
void showSplashWithBootCheck(const char* version);

/// Show hardware check progress. Call multiple times as each subsystem initializes.
/// status: 0=checking, 1=ok, 2=failed, 3=skipped
void showHardwareCheck(const char* component, uint8_t status);

/// Show first-boot introduction screen (new device, never been set up).
/// Explains what Aksabot is before BLE provisioning begins.
void showFirstBoot();

/// Show provisioning prompt. Pass the SoftAP name so users see both options.
/// apName may be nullptr when SoftAP is not active.
void showProvisioningPrompt(const char* apName = nullptr);

/// Show "Phone Connected" screen when BLE client connects during provisioning.
/// Replaces the provisioning prompt with setup-in-progress UI.
void showProvisioningConnected();

/// Update provisioning status line (e.g., "Phone connected!", "Receiving WiFi...").
void showProvisioningStatus(const char* status);

/// Animate the provisioning waiting indicator (call in a loop while blocking).
/// Cycles three dots so the screen never looks frozen. Safe to call every 100ms.
void tickProvisioningAnimation(uint32_t nowMs);

/// Show setup complete celebration (first successful WiFi connection).
void showSetupComplete(const char* ssid);

/// Show WiFi connecting progress.
void showConnecting(const char* ssid);

/// Show connection result.
void showConnected(const char* ip);
void showConnectionFailed(const char* reason);

/// Show "Ready!" and transition hint.
void showReady();

/// Show "Entering Setup Mode" screen when the app requests remote re-provisioning.
/// Device will reboot in ~1.5s; this screen stays up until the restart.
void showRebootingForSetup();

/// Show "Hold screen for BIOS..." with a 2-second countdown bar.
/// Returns true if the user held the screen during the countdown (enter BIOS).
/// Returns false if the countdown expired without a hold (continue boot).
bool showBiosCountdown();

}  // namespace boot_screen
