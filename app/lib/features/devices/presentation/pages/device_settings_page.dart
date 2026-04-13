import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../domain/repositories/devices_repository.dart';
import 'ble_provisioning_page.dart';

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
      (_) {
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

          // Network
          Text('Network', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.wifi),
              title: const Text('Change Wi-Fi'),
              subtitle: const Text('Connect Aksabot to a different network'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const BleProvisioningPage(changeWifiMode: true),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
