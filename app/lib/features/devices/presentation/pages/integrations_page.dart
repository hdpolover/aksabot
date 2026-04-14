import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../domain/entities/device_entity.dart';
import '../../domain/repositories/devices_repository.dart';

/// Integrations management screen.
/// Toggle states are persisted via PATCH /devices/:id/settings.
class IntegrationsPage extends StatefulWidget {
  final String deviceId;
  const IntegrationsPage({super.key, required this.deviceId});

  @override
  State<IntegrationsPage> createState() => _IntegrationsPageState();
}

class _IntegrationsPageState extends State<IntegrationsPage> {
  final _devicesRepo = sl<DevicesRepository>();

  bool _loading = true;
  bool _saving = false;

  bool _weatherEnabled = false;
  double? _latitude;
  double? _longitude;
  String? _locationStatus;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    final result = await _devicesRepo.getDevice(widget.deviceId);
    if (!mounted) return;
    result.fold(
      (_) => setState(() => _loading = false),
      (device) => _applySettings(device),
    );
  }

  void _applySettings(Device device) {
    final s = device.settingsJson;
    setState(() {
      _weatherEnabled = s['integrations_weather'] as bool? ?? false;
      _latitude = (s['latitude'] as num?)?.toDouble();
      _longitude = (s['longitude'] as num?)?.toDouble();
      _loading = false;
    });
  }

  Future<void> _saveSettings(Map<String, dynamic> patch) async {
    if (_saving) return;
    setState(() => _saving = true);

    final result = await _devicesRepo.updateSettings(widget.deviceId, patch);
    if (!mounted) return;

    result.fold(
      (failure) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: ${failure.message}')),
        );
      },
      (device) {
        _applySettings(device);
        setState(() => _saving = false);
      },
    );
  }

  Future<void> _toggleWeather(bool enabled) async {
    if (enabled) {
      // Request location when enabling weather
      final hasLocation = await _requestLocation();
      if (!hasLocation) {
        // Permission denied or location unavailable
        return;
      }
      setState(() => _weatherEnabled = true);
      await _saveSettings({'integrations_weather': true});
    } else {
      setState(() => _weatherEnabled = false);
      await _saveSettings({'integrations_weather': false});
    }
  }

  Future<bool> _requestLocation() async {
    setState(() => _locationStatus = 'Checking permissions...');

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return false;
      setState(() => _locationStatus = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services are disabled. Enable them in settings.')),
      );
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return false;
        setState(() => _locationStatus = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied.')),
        );
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return false;
      setState(() => _locationStatus = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission permanently denied. Enable in system settings.')),
      );
      return false;
    }

    setState(() => _locationStatus = 'Getting location...');

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (!mounted) return false;

      // Save location to device settings (timezone auto-detected by server)
      await _saveSettings({
        'latitude': position.latitude,
        'longitude': position.longitude,
      });

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationStatus = null;
      });

      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _locationStatus = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get location: $e')),
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Integrations')),
        body: const AppLoadingIndicator(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Integrations'),
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
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.cloud, color: colors.primary),
                  title: const Text('Weather'),
                  subtitle: Text(
                    _weatherEnabled && _latitude != null
                        ? 'Open-Meteo (${_latitude!.toStringAsFixed(1)}, ${_longitude!.toStringAsFixed(1)})'
                        : 'Open-Meteo — injects local weather into Aksa\'s context',
                  ),
                  value: _weatherEnabled,
                  onChanged: _saving ? null : _toggleWeather,
                ),
                if (_locationStatus != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _locationStatus!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_weatherEnabled && _latitude != null)
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.my_location, size: 20, color: colors.onSurfaceVariant),
                    title: Text(
                      'Location: ${_latitude!.toStringAsFixed(2)}, ${_longitude!.toStringAsFixed(2)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: TextButton(
                      onPressed: _saving ? null : _requestLocation,
                      child: const Text('Update'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

