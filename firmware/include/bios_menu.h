#pragma once

/// BIOS Menu — diagnostic/setup menu accessible during boot.
///
/// Triggered by holding the touchscreen during a 2-second countdown after POST.
/// Provides: Continue Boot, Audio Test, WiFi Scan, System Info, Setup WiFi.
namespace bios_menu {

/// Show the BIOS menu (blocking). Call after POST, before WiFi provisioning.
/// Returns true if the user selected "Setup WiFi" (caller should enter provisioning).
/// Returns false for "Continue Boot" or any other exit path.
bool show();

}  // namespace bios_menu
