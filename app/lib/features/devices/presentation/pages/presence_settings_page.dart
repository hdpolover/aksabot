import 'package:flutter/material.dart';

import '../../../../core/ble/ble_presence_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_loading_indicator.dart';

/// Presence detection settings — wired to BLE presence advertising service.
class PresenceSettingsPage extends StatefulWidget {
  final String deviceId;
  const PresenceSettingsPage({super.key, required this.deviceId});

  @override
  State<PresenceSettingsPage> createState() => _PresenceSettingsPageState();
}

class _PresenceSettingsPageState extends State<PresenceSettingsPage> {
  late final BlePresenceService _presence;

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
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final supported = await _presence.isSupported;
    final enabled = await _presence.loadEnabled();
    final rssi = await _presence.loadRssiThreshold();
    final grace = await _presence.loadGracePeriod();
    final silent = await _presence.loadSilentWakeMinutes();

    // Check actual advertising state
    await _presence.checkAdvertisingState();

    if (!mounted) return;
    setState(() {
      _isSupported = supported;
      _enabled = enabled && supported;
      _rssiThreshold = rssi;
      _gracePeriod = grace.toString();
      _silentWake = silent.toString();
      _isLoading = false;
    });
  }

  Future<void> _togglePresence(bool enabled) async {
    setState(() => _enabled = enabled);

    if (enabled) {
      final started = await _presence.startAdvertising();
      if (started) {
        await _presence.saveEnabled(true);
      } else {
        await _presence.saveEnabled(false);
        if (!mounted) return;
        setState(() => _enabled = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start BLE advertising. Check Bluetooth permissions.')),
        );
      }
    } else {
      await _presence.stopAdvertising();
      await _presence.saveEnabled(false);
    }
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

          // Enable toggle
          Card(
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              secondary: Icon(Icons.bluetooth_searching, color: colors.primary),
              title: const Text('Enable presence'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'When your phone is nearby, Aksa wakes up and greets you. '
                    'When you leave, Aksa goes to sleep.',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _enabled && _presence.isAdvertising
                        ? 'Advertising...'
                        : 'Not advertising',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _enabled
                          ? Theme.of(context).extension<AppColors>()!.success
                          : colors.outline,
                    ),
                  ),
                ],
              ),
              value: _enabled,
              onChanged: _isSupported ? _togglePresence : null,
            ),
          ),
          const SizedBox(height: 24),

          // Sensitivity
          Text('Sensitivity', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Farther', style: theme.textTheme.bodySmall),
                      Text('Closer', style: theme.textTheme.bodySmall),
                    ],
                  ),
                  Slider(
                    value: _rssiThreshold,
                    min: -90,
                    max: -60,
                    divisions: 6,
                    label: '${_rssiThreshold.round()} dBm',
                    onChanged: _enabled
                        ? (v) {
                            setState(() => _rssiThreshold = v);
                            _presence.saveRssiThreshold(v);
                          }
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: colors.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'RSSI threshold for the ESP32. Values closer to 0 = shorter range.',
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
                      const Text('Grace period'),
                      DropdownButton<String>(
                        value: _gracePeriod,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: '15', child: Text('15 sec')),
                          DropdownMenuItem(value: '30', child: Text('30 sec')),
                          DropdownMenuItem(value: '45', child: Text('45 sec')),
                          DropdownMenuItem(value: '60', child: Text('60 sec')),
                        ],
                        onChanged: _enabled
                            ? (v) {
                                if (v != null) {
                                  setState(() => _gracePeriod = v);
                                  _presence.saveGracePeriod(int.parse(v));
                                }
                              }
                            : null,
                      ),
                    ],
                  ),
                  Text(
                    'Delay before sleep after losing signal.',
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
          Text('Behavior', style: theme.textTheme.titleMedium),
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
                      const Text('Silent wake if away less than'),
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
                                }
                              }
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Skips the greeting if you just stepped away briefly.',
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
