import 'package:flutter/material.dart';

import '../../../../core/ble/ble_presence_service.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../domain/repositories/devices_repository.dart';

/// Presence detection settings — wired to the BLE scan service.
/// The phone scans for the ESP32's advertisement and reports presence to
/// the backend, which triggers greetings and departure animations.
class PresenceSettingsPage extends StatefulWidget {
  final String deviceId;
  const PresenceSettingsPage({super.key, required this.deviceId});

  @override
  State<PresenceSettingsPage> createState() => _PresenceSettingsPageState();
}

class _PresenceSettingsPageState extends State<PresenceSettingsPage> {
  late final BlePresenceService _presence;
  late final DevicesRepository _devicesRepo;

  bool _enabled = false;
  bool _isLoading = true;
  double _rssiThreshold = -75;
  String _gracePeriod = '45';
  String _silentWake = '5';

  @override
  void initState() {
    super.initState();
    _presence = sl<BlePresenceService>();
    _devicesRepo = sl<DevicesRepository>();
    _loadSettings();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadSettings() async {
    bool enabled = false;
    double rssi = -75.0;
    int grace = 45;
    int silent = 5;

    try {
      enabled = await _presence.loadEnabled();
      rssi = await _presence.loadRssiThreshold();
      grace = await _presence.loadGracePeriod();
      silent = await _presence.loadSilentWakeMinutes();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _rssiThreshold = rssi;
      _gracePeriod = grace.toString();
      _silentWake = silent.toString();
      _isLoading = false;
    });
  }

  String _rssiLabel(double rssi) {
    if (rssi >= -65) return 'Very close';
    if (rssi >= -72) return 'Nearby';
    if (rssi >= -80) return 'Same room';
    return 'Far away';
  }

  Future<void> _syncToBackend(Map<String, dynamic> patch) async {
    await _devicesRepo.updateSettings(widget.deviceId, patch);
  }

  Future<void> _togglePresence(bool enabled) async {
    setState(() => _enabled = enabled);

    if (enabled) {
      await _presence.configureDevice(widget.deviceId);
      await _presence.saveEnabled(true);
      final started = await _presence.startScanning();
      if (!started && mounted) {
        setState(() => _enabled = false);
        await _presence.saveEnabled(false);
        _showBluetoothErrorDialog();
        return;
      }
      _syncToBackend({'presence_enabled': true});
    } else {
      await _presence.stopScanning();
      await _presence.saveEnabled(false);
      _syncToBackend({'presence_enabled': false});
    }
    if (mounted) setState(() {});
  }

  void _showBluetoothErrorDialog() {
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
                  'Presence detection needs Bluetooth to scan for your device. '
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
          // ── Live status ──────────────────────────────────────────────────
          ListenableBuilder(
            listenable: _presence,
            builder: (context, child) => _PresenceStatusCard(
              enabled: _enabled,
              isPresent: _presence.isPresent,
              isScanning: _presence.isScanning,
              lastError: _presence.lastError,
              onRetry: () => _togglePresence(true),
            ),
          ),
          const SizedBox(height: 16),

          // Enable toggle
          Card(
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              secondary: Icon(Icons.sensors_rounded, color: colors.primary),
              title: const Text('Enable presence'),
              subtitle: const Text(
                'When you sit at your desk, Aksa wakes up and greets you. '
                'When you leave, Aksa goes to sleep.',
              ),
              value: _enabled,
              onChanged: _togglePresence,
            ),
          ),
          const SizedBox(height: 24),

          // Detection range
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
                        ? (v) => _syncToBackend(
                            {'presence_rssi_threshold': v.round()})
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: colors.onSurfaceVariant),
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
                          DropdownMenuItem(
                              value: '15', child: Text('15 sec')),
                          DropdownMenuItem(
                              value: '30', child: Text('30 sec')),
                          DropdownMenuItem(
                              value: '45', child: Text('45 sec')),
                          DropdownMenuItem(value: '60', child: Text('1 min')),
                        ],
                        onChanged: _enabled
                            ? (v) {
                                if (v != null) {
                                  setState(() => _gracePeriod = v);
                                  _presence.saveGracePeriod(int.parse(v));
                                  _syncToBackend(
                                      {'presence_grace_period': int.parse(v)});
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

          // Greeting behavior
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
                      const Expanded(
                          child: Text('Skip greeting if away less than')),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _silentWake,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: '2', child: Text('2 min')),
                          DropdownMenuItem(value: '5', child: Text('5 min')),
                          DropdownMenuItem(
                              value: '10', child: Text('10 min')),
                        ],
                        onChanged: _enabled
                            ? (v) {
                                if (v != null) {
                                  setState(() => _silentWake = v);
                                  _presence.saveSilentWakeMinutes(int.parse(v));
                                  _syncToBackend({
                                    'presence_silent_wake_minutes': int.parse(v)
                                  });
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
// Live scan status card
// ---------------------------------------------------------------------------

class _PresenceStatusCard extends StatelessWidget {
  final bool enabled;
  final bool isPresent;
  final bool isScanning;
  final String? lastError;
  final VoidCallback onRetry;

  const _PresenceStatusCard({
    required this.enabled,
    required this.isPresent,
    required this.isScanning,
    required this.lastError,
    required this.onRetry,
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
      subtitle = 'Enable the toggle below to start scanning.';
    } else if (isPresent) {
      bgColor = ac.successContainer;
      iconColor = ac.success;
      icon = Icons.sensors_rounded;
      title = 'Device detected nearby';
      subtitle = 'Aksa knows you are at your desk.';
    } else if (isScanning) {
      bgColor = cs.surfaceContainerHigh;
      iconColor = cs.primary;
      icon = Icons.radar_rounded;
      title = 'Scanning for device…';
      subtitle = 'Looking for your Aksabot nearby.';
    } else {
      bgColor = cs.surfaceContainerHigh;
      iconColor = cs.onSurfaceVariant;
      icon = Icons.sensors_off_rounded;
      title = 'Not scanning';
      subtitle = 'Scanning will resume when the app is active.';
    }

    final hasError = enabled && !isPresent && lastError != null;

    return Card(
      color: hasError ? cs.errorContainer : bgColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingLg,
          vertical: AppConstants.spacingMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasError ? Icons.bluetooth_disabled_rounded : icon,
                  color: hasError ? cs.onErrorContainer : iconColor,
                  size: AppConstants.iconLg,
                ),
                const SizedBox(width: AppConstants.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasError ? 'Bluetooth error' : title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: hasError
                              ? cs.onErrorContainer
                              : (enabled ? iconColor : cs.onSurfaceVariant),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasError ? lastError! : subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: hasError
                              ? cs.onErrorContainer
                              : (enabled
                                  ? (isPresent ? ac.success : cs.onSurfaceVariant)
                                  : cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasError)
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
