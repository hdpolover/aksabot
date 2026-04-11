import 'package:flutter/material.dart';

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

  // Integration toggles — keyed by settings field name.
  bool _weatherEnabled = false;

  // The settings snapshot from the server (may contain keys we don't render).
  Map<String, dynamic> _rawSettings = {};

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
      _rawSettings = Map<String, dynamic>.from(s);
      _weatherEnabled = s['integrations_weather'] as bool? ?? false;
      _loading = false;
    });
  }

  Future<void> _saveSettings(String key, dynamic value) async {
    if (_saving) return;
    setState(() => _saving = true);

    final patch = {key: value};

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
          // Connected
          Text('Connected', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              secondary: Icon(Icons.cloud, color: colors.primary),
              title: const Text('Weather'),
              subtitle: const Text('OpenWeatherMap'),
              value: _weatherEnabled,
              onChanged: _saving
                  ? null
                  : (v) {
                      setState(() => _weatherEnabled = v);
                      _saveSettings('integrations_weather', v);
                    },
            ),
          ),
          const SizedBox(height: 24),

          // Available (coming soon — no toggle, no persistence yet)
          Text('Available', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _ComingSoonTile(
                  icon: Icons.calendar_today,
                  name: 'Google Calendar',
                  description: 'Morning briefing, events',
                  color: colors.primary,
                ),
                const Divider(height: 1),
                _ComingSoonTile(
                  icon: Icons.newspaper,
                  name: 'News',
                  description: 'Headlines in briefing',
                  color: colors.tertiary,
                ),
                const Divider(height: 1),
                _ComingSoonTile(
                  icon: Icons.home,
                  name: 'Home Assistant',
                  description: 'Smart home voice control',
                  color: colors.secondary,
                ),
                const Divider(height: 1),
                _ComingSoonTile(
                  icon: Icons.music_note,
                  name: 'Spotify',
                  description: 'Music control via voice',
                  color: Theme.of(context).extension<AppColors>()!.success,
                ),
                const Divider(height: 1),
                _ComingSoonTile(
                  icon: Icons.checklist,
                  name: 'Todoist',
                  description: 'Task management via voice',
                  color: Theme.of(context).colorScheme.error,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Integrations let Aksa access external services to give you '
            'richer responses and control.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComingSoonTile extends StatelessWidget {
  final IconData icon;
  final String name;
  final String description;
  final Color color;

  const _ComingSoonTile({
    required this.icon,
    required this.name,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(name),
      subtitle: Text(description),
      trailing: FilledButton.tonal(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$name integration coming soon')),
          );
        },
        child: const Text('Connect'),
      ),
    );
  }
}
