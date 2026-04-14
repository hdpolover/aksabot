import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
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
  String? _locationStatus; // non-null = in-progress message

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
      final hasLocation = await _requestLocation();
      if (!hasLocation) return;
      setState(() => _weatherEnabled = true);
      await _saveSettings({'integrations_weather': true});
    } else {
      setState(() => _weatherEnabled = false);
      await _saveSettings({'integrations_weather': false});
    }
  }

  Future<bool> _requestLocation() async {
    setState(() => _locationStatus = 'Checking permissions…');

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return false;
      setState(() => _locationStatus = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location services are disabled. Enable them in Settings.'),
        ),
      );
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return false;
      setState(() => _locationStatus = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location permission required. Enable it in system Settings.',
          ),
        ),
      );
      return false;
    }

    setState(() => _locationStatus = 'Getting your location…');

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return false;

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

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Human-readable coordinates, e.g. "3.1°N, 101.7°E"
  String _formatCoords(double lat, double lon) {
    final latDir = lat >= 0 ? 'N' : 'S';
    final lonDir = lon >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(1)}°$latDir, '
        '${lon.abs().toStringAsFixed(1)}°$lonDir';
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ── Active integrations ───────────────────────────────────────
          _SectionLabel(label: 'Data Sources'),
          const SizedBox(height: 8),
          _WeatherCard(
            enabled: _weatherEnabled,
            saving: _saving,
            latitude: _latitude,
            longitude: _longitude,
            locationStatus: _locationStatus,
            onToggle: _toggleWeather,
            onUpdateLocation: _requestLocation,
            formatCoords: _formatCoords,
          ),
          const SizedBox(height: 24),

          // ── Coming soon ───────────────────────────────────────────────
          _SectionLabel(label: 'Coming Soon'),
          const SizedBox(height: 8),
          _ComingSoonCard(
            icon: Icons.calendar_month_rounded,
            iconColor: colors.primary,
            title: 'Google Calendar',
            description:
                'Aksa announces upcoming meetings, blocks focus mode during events, and greets you after long calls.',
          ),
          const SizedBox(height: 8),
          _ComingSoonCard(
            icon: Icons.code_rounded,
            iconColor: theme.extension<AppColors>()!.info,
            title: 'GitHub',
            description:
                'Get notified about PR review requests, failed CI builds, and issues assigned to you — without opening a browser.',
          ),
          const SizedBox(height: 8),
          _ComingSoonCard(
            icon: Icons.music_note_rounded,
            iconColor: theme.extension<AppColors>()!.success,
            title: 'Spotify',
            description:
                'See what\'s playing on the display, skip or pause by voice, and auto-pause when you leave the desk.',
          ),
          const SizedBox(height: 8),
          _ComingSoonCard(
            icon: Icons.monitor_heart_rounded,
            iconColor: theme.extension<AppColors>()!.warning,
            title: 'System Metrics',
            description:
                'A small desktop daemon pushes CPU and RAM usage. Aksa warns you when a build or Docker container is overloading your machine.',
          ),
        ],
      ),
    );
  }
}

// ── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(label, style: Theme.of(context).textTheme.titleMedium);
  }
}

// ── Weather card ─────────────────────────────────────────────────────────────

class _WeatherCard extends StatelessWidget {
  final bool enabled;
  final bool saving;
  final double? latitude;
  final double? longitude;
  final String? locationStatus;
  final ValueChanged<bool> onToggle;
  final VoidCallback onUpdateLocation;
  final String Function(double lat, double lon) formatCoords;

  const _WeatherCard({
    required this.enabled,
    required this.saving,
    required this.latitude,
    required this.longitude,
    required this.locationStatus,
    required this.onToggle,
    required this.onUpdateLocation,
    required this.formatCoords,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColors>()!;
    final hasLocation = latitude != null && longitude != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── Header row ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                _IntegrationIcon(
                  icon: Icons.wb_sunny_rounded,
                  color: colors.tertiary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Weather',
                            style: theme.textTheme.titleSmall,
                          ),
                          if (enabled) ...[
                            const SizedBox(width: 8),
                            _StatusChip(
                              label: 'Active',
                              color: appColors.success,
                              onColor: appColors.onSuccess,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Open-Meteo · free, no API key required',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: enabled,
                  onChanged: saving ? null : onToggle,
                ),
              ],
            ),
          ),

          // ── Description ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              'Injects your local temperature, humidity, and conditions into '
              'Aksa\'s context every 15 minutes. She\'ll mention the weather '
              'naturally in conversation and factor it into reminders.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),

          // ── Location progress ────────────────────────────────────────
          if (locationStatus != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    locationStatus!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Location row (when active) ───────────────────────────────
          if (enabled && hasLocation && locationStatus == null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on_rounded,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    formatCoords(latitude!, longitude!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: saving ? null : onUpdateLocation,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 36),
                    ),
                    child: const Text('Update location'),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ── Coming soon card ─────────────────────────────────────────────────────────

class _ComingSoonCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  const _ComingSoonCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Opacity(
      opacity: 0.55,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IntegrationIcon(icon: icon, color: iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title, style: theme.textTheme.titleSmall),
                        const SizedBox(width: 8),
                        _StatusChip(
                          label: 'Coming soon',
                          color: colors.onSurfaceVariant,
                          onColor: colors.surface,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _IntegrationIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IntegrationIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color onColor;

  const _StatusChip({
    required this.label,
    required this.color,
    required this.onColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
