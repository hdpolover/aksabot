import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../../../core/widgets/status_dot.dart';
import '../../domain/entities/device_entity.dart';
import '../../domain/repositories/devices_repository.dart';

/// Device settings page — volume, brightness, transcript, idle timeout, device info.
/// Navigated from the "Settings" quick action on the device dashboard.
class DeviceSettingsPage extends StatefulWidget {
  final String deviceId;
  const DeviceSettingsPage({super.key, required this.deviceId});

  @override
  State<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

class _DeviceSettingsPageState extends State<DeviceSettingsPage> {
  final _devicesRepo = sl<DevicesRepository>();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  Device? _device;

  double _volume = 70;
  double _brightness = 70;
  bool _showTranscript = false;
  String _idleTimeout = '30';


  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _devicesRepo.getDevice(widget.deviceId);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _loading = false;
      }),
      (device) {
        final s = device.settingsJson;
        final timeoutSec = (s['idle_timeout_seconds'] as num?)?.toInt();
        final vol = (s['volume'] as num?)?.toDouble();
        final br = (s['brightness'] as num?)?.toDouble();
        final tr = s['display_transcript'] as bool?;
        final minutes = timeoutSec != null ? (timeoutSec ~/ 60) : 30;
        setState(() {
          _device = device;
          _volume = vol ?? 70;
          _brightness = br ?? 70;
          _showTranscript = tr ?? false;
          _idleTimeout =
              const ['1', '5', '10', '30'].contains(minutes.toString())
                  ? minutes.toString()
                  : '30';
          _loading = false;
        });
      },
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    // Always send all settings from this page — backend merges per-key,
    // so this only touches volume/brightness/transcript/timeout.
    final result = await _devicesRepo.updateSettings(widget.deviceId, {
      'volume': _volume.round(),
      'brightness': _brightness.round(),
      'display_transcript': _showTranscript,
      'idle_timeout_seconds': int.parse(_idleTimeout) * 60,
    });
    if (!mounted) return;

    result.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: ${failure.message}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      },
      (device) {
        // Update device ref for future diff checks, but keep local slider values
        setState(() => _device = device);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved')),
        );
      },
    );

    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const AppLoadingIndicator(),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colors.error),
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: colors.error)),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _loadSettings,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final device = _device!;
    final online = device.isOnline;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // General section
          Text('General', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Volume', style: theme.textTheme.bodyMedium),
                      const Spacer(),
                      Text('${_volume.round()}%',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                  Slider(
                    value: _volume,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    onChanged: (v) => setState(() => _volume = v),
                  ),
                  Row(
                    children: [
                      Text('Brightness', style: theme.textTheme.bodyMedium),
                      const Spacer(),
                      Text('${_brightness.round()}%',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                  Slider(
                    value: _brightness,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    onChanged: (v) => setState(() => _brightness = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Show transcript',
                          style: theme.textTheme.bodyMedium),
                      Switch(
                        value: _showTranscript,
                        onChanged: (v) =>
                            setState(() => _showTranscript = v),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Idle timeout',
                          style: theme.textTheme.bodyMedium),
                      DropdownButton<String>(
                        value: _idleTimeout,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(
                              value: '1', child: Text('1 min')),
                          DropdownMenuItem(
                              value: '5', child: Text('5 min')),
                          DropdownMenuItem(
                              value: '10', child: Text('10 min')),
                          DropdownMenuItem(
                              value: '30', child: Text('30 min')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _idleTimeout = v);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save Settings'),
          ),
          const SizedBox(height: AppConstants.spacingXxl),

          // Device info
          Text('Device Info', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  title: const Text('Status'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusDot(
                        variant: online
                            ? StatusDotVariant.online
                            : StatusDotVariant.offline,
                      ),
                      const SizedBox(width: AppConstants.spacingSm),
                      Text(
                        online ? 'Online' : 'Offline',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Wi-Fi signal'),
                  trailing: device.wifiRssi != null
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _wifiIcon(device.wifiRssi!),
                              size: 18,
                              color: _wifiColor(device.wifiRssi!, colors),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _wifiLabel(device.wifiRssi!),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    _wifiColor(device.wifiRssi!, colors),
                              ),
                            ),
                          ],
                        )
                      : Text(
                          online ? 'Connected' : 'N/A',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Firmware'),
                  trailing: Text(
                    device.firmwareVersion ?? 'N/A',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _wifiLabel(int rssi) {
    if (rssi > -50) return 'Excellent';
    if (rssi > -60) return 'Good';
    if (rssi > -70) return 'Fair';
    if (rssi > -80) return 'Weak';
    return 'Poor';
  }

  static IconData _wifiIcon(int rssi) {
    if (rssi > -60) return Icons.wifi;
    if (rssi > -70) return Icons.wifi_2_bar;
    return Icons.wifi_1_bar;
  }

  static Color _wifiColor(int rssi, ColorScheme colors) {
    if (rssi > -60) return colors.primary;
    if (rssi > -70) return colors.tertiary;
    return colors.error;
  }
}
