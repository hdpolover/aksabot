import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart'; // PeripheralState

import '../../../../core/ble/ble_presence_service.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../domain/repositories/devices_repository.dart';

/// Presence detection settings — wired to BLE presence advertising service.
class PresenceSettingsPage extends StatefulWidget {
  final String deviceId;
  const PresenceSettingsPage({super.key, required this.deviceId});

  @override
  State<PresenceSettingsPage> createState() => _PresenceSettingsPageState();
}

class _PresenceSettingsPageState extends State<PresenceSettingsPage> {
  late final BlePresenceService _presence;
  late final DevicesRepository _devicesRepo;
  StreamSubscription<PeripheralState>? _stateSub;

  bool _enabled = false;
  bool _isLoading = true;
  bool _isSupported = true;
  double _rssiThreshold = -75;
  String _gracePeriod = '45';
  String _silentWake = '5';

  @override
  void initState() {
    super.initState();
    _presence = sl<BlePresenceService>();
    _devicesRepo = sl<DevicesRepository>();
    _loadSettings();
    _listenBleState();
  }

  void _listenBleState() {
    try {
      _stateSub = _presence.peripheralStateStream?.listen((state) {
        if (!mounted) return;
        // Only update UI — don't call start/stop advertising here to avoid
        // "Reply already submitted" crash in the plugin when BT toggles.
        setState(() {
          if (state == PeripheralState.poweredOff) {
            _enabled = false;
          }
        });
      });
    } catch (_) {
      // BLE peripheral stream unavailable on this device — ignore.
    }
  }

  Future<void> _refreshAdvertisingState() async {
    final isNowAdvertising = await _presence.checkAdvertisingState();
    if (mounted) setState(() {});
    // If saved as enabled but not actually advertising, try to restart.
    if (_enabled && !isNowAdvertising) {
      await _presence.startAdvertising();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    bool supported = false;
    bool enabled = false;
    double rssi = -75.0;
    int grace = 45;
    int silent = 5;

    try {
      supported = await _presence.isSupported;
    } catch (_) {}

    try {
      enabled = await _presence.loadEnabled();
      rssi = await _presence.loadRssiThreshold();
      grace = await _presence.loadGracePeriod();
      silent = await _presence.loadSilentWakeMinutes();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _isSupported = supported;
      // Show the user's saved preference, not the hardware state.
      // If BLE isn't supported, force off.
      _enabled = supported ? enabled : false;
      _rssiThreshold = rssi;
      _gracePeriod = grace.toString();
      _silentWake = silent.toString();
      _isLoading = false;
    });
  }

  /// Maps raw RSSI threshold (–90 to –60) to a human-readable range label.
  String _rssiLabel(double rssi) {
    if (rssi >= -65) return 'Very close';
    if (rssi >= -72) return 'Nearby';
    if (rssi >= -80) return 'Same room';
    return 'Far away';
  }

  /// Sync a presence setting to the backend so the ESP32 gets it via WebSocket.
  Future<void> _syncToBackend(Map<String, dynamic> patch) async {
    await _devicesRepo.updateSettings(widget.deviceId, patch);
  }

  Future<void> _togglePresence(bool enabled) async {
    setState(() => _enabled = enabled);

    if (enabled) {
      final started = await _presence.startAdvertising();
      if (started) {
        await _presence.saveEnabled(true);
        _syncToBackend({'presence_enabled': true});
        if (mounted) setState(() {}); // refresh advertising status text
      } else {
        await _presence.saveEnabled(false);
        if (!mounted) return;
        setState(() => _enabled = false);
        _showPermissionDialog();
      }
    } else {
      await _presence.stopAdvertising();
      await _presence.saveEnabled(false);
      _syncToBackend({'presence_enabled': false});
    }
  }

  void _showPermissionDialog() {
    final errorDetail = _presence.lastError ?? 'Unknown error';
    showDialog(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.bluetooth_disabled, size: 40, color: colors.error),
          title: const Text('Bluetooth Required'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Presence detection needs Bluetooth advertising to work. '
                  'Make sure Bluetooth is on and permissions are granted.',
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    errorDetail,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.end,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await FlutterBlePeripheral().openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                _togglePresence(true);
              },
              child: const Text('Try Again'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Presence Detection')),
        body: const AppLoadingIndicator(),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Presence Detection')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_isSupported) ...[
            Card(
              color: colors.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: colors.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'BLE peripheral mode is not supported on this device.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Live advertising status ──────────────────────────────────
          _PresenceStatusCard(
            enabled: _enabled,
            isAdvertising: _presence.isAdvertising,
            lastError: _presence.lastError,
            onRefresh: _refreshAdvertisingState,
          ),
          const SizedBox(height: 16),

          // Enable toggle
          Card(
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              secondary: Icon(Icons.bluetooth_searching, color: colors.primary),
              title: const Text('Enable presence'),
              subtitle: const Text(
                'When your phone is nearby, Aksa wakes up and greets you. '
                'When you leave, Aksa goes to sleep.',
              ),
              value: _enabled,
              onChanged: _isSupported ? _togglePresence : null,
            ),
          ),
          const SizedBox(height: 24),

          // Sensitivity
          Text('Detection range', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Far away', style: theme.textTheme.bodySmall),
                      Text('Very close', style: theme.textTheme.bodySmall),
                    ],
                  ),
                  Slider(
                    value: _rssiThreshold,
                    min: -90,
                    max: -60,
                    divisions: 6,
                    label: _rssiLabel(_rssiThreshold),
                    onChanged: _enabled
                        ? (v) {
                            setState(() => _rssiThreshold = v);
                            _presence.saveRssiThreshold(v);
                          }
                        : null,
                    onChangeEnd: _enabled
                        ? (v) => _syncToBackend({'presence_rssi_threshold': v.round()})
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: colors.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'How close you need to be for Aksa to detect you. '
                          'Start with "Nearby" — adjust if it triggers too early or too late.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Sleep delay'),
                      DropdownButton<String>(
                        value: _gracePeriod,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: '15', child: Text('15 sec')),
                          DropdownMenuItem(value: '30', child: Text('30 sec')),
                          DropdownMenuItem(value: '45', child: Text('45 sec')),
                          DropdownMenuItem(value: '60', child: Text('1 min')),
                        ],
                        onChanged: _enabled
                            ? (v) {
                                if (v != null) {
                                  setState(() => _gracePeriod = v);
                                  _presence.saveGracePeriod(int.parse(v));
                                  _syncToBackend({'presence_grace_period': int.parse(v)});
                                }
                              }
                            : null,
                      ),
                    ],
                  ),
                  Text(
                    'How long to wait after you leave before Aksa goes to sleep.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Behavior
          Text('Greeting behavior', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(child: Text('Skip greeting if away less than')),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _silentWake,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: '2', child: Text('2 min')),
                          DropdownMenuItem(value: '5', child: Text('5 min')),
                          DropdownMenuItem(value: '10', child: Text('10 min')),
                        ],
                        onChanged: _enabled
                            ? (v) {
                                if (v != null) {
                                  setState(() => _silentWake = v);
                                  _presence.saveSilentWakeMinutes(int.parse(v));
                                  _syncToBackend({'presence_silent_wake_minutes': int.parse(v)});
                                }
                              }
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Aksa won't say hello if you just stepped away for a moment.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Live advertising status card
// ---------------------------------------------------------------------------

class _PresenceStatusCard extends StatelessWidget {
  final bool enabled;
  final bool isAdvertising;
  final String? lastError;
  final VoidCallback onRefresh;

  const _PresenceStatusCard({
    required this.enabled,
    required this.isAdvertising,
    required this.lastError,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ac = theme.extension<AppColors>()!;

    final Color bgColor;
    final Color iconColor;
    final IconData icon;
    final String title;
    final String subtitle;

    if (!enabled) {
      bgColor = cs.surfaceContainerHigh;
      iconColor = cs.onSurfaceVariant;
      icon = Icons.sensors_off_rounded;
      title = 'Presence detection is off';
      subtitle = 'Enable the toggle below to start broadcasting.';
    } else if (isAdvertising) {
      bgColor = ac.successContainer;
      iconColor = ac.success;
      icon = Icons.sensors_rounded;
      title = 'Phone is broadcasting';
      subtitle = 'Your device can detect you nearby.';
    } else {
      bgColor = cs.errorContainer;
      iconColor = cs.onErrorContainer;
      icon = Icons.sensors_off_rounded;
      title = 'Not broadcasting';
      subtitle = lastError ?? 'Check that Bluetooth is enabled and permissions are granted.';
    }

    return Card(
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingLg,
          vertical: AppConstants.spacingMd,
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: AppConstants.iconLg),
            const SizedBox(width: AppConstants.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: enabled ? iconColor : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: enabled
                          ? (isAdvertising ? ac.success : cs.onErrorContainer)
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (enabled && !isAdvertising)
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                color: cs.onErrorContainer,
                tooltip: 'Retry',
                onPressed: onRefresh,
              ),
          ],
        ),
      ),
    );
  }
}
