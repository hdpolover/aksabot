import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Desk Mobility settings — planned UI (future hardware extension).
class MobilitySettingsPage extends StatefulWidget {
  final String deviceId;
  const MobilitySettingsPage({super.key, required this.deviceId});

  @override
  State<MobilitySettingsPage> createState() => _MobilitySettingsPageState();
}

class _MobilitySettingsPageState extends State<MobilitySettingsPage> {
  bool _enabled = false;
  double _speed = 0.5;
  bool _wanderWhenIdle = false;
  bool _comeCloserWhenTalking = true;
  final bool _calibrated = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Desk Mobility')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Enable toggle
          Card(
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              secondary: Icon(Icons.open_with, color: colors.primary),
              title: const Text('Enable mobility'),
              subtitle: const Text(
                'Aksa can move around your desk using its wheels.',
              ),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
          ),
          const SizedBox(height: 24),

          // Movement
          Text('Movement', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text('Speed', style: theme.textTheme.bodyMedium),
                    ],
                  ),
                  Row(
                    children: [
                      Text('Slow', style: theme.textTheme.bodySmall),
                      Expanded(
                        child: Slider(
                          value: _speed,
                          onChanged: _enabled
                              ? (v) => setState(() => _speed = v)
                              : null,
                        ),
                      ),
                      Text('Normal', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Wander when idle'),
                  value: _wanderWhenIdle,
                  onChanged: _enabled
                      ? (v) => setState(() => _wanderWhenIdle = v)
                      : null,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Come closer when talking'),
                  value: _comeCloserWhenTalking,
                  onChanged: _enabled
                      ? (v) => setState(() => _comeCloserWhenTalking = v)
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Safety
          Text('Safety', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.tonal(
                    onPressed: _enabled
                        ? () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Boundary calibration requires hardware')),
                            );
                          }
                        : null,
                    child: const Text('Learn Desk Boundaries'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Drive Aksa to each edge of your desk to teach it the safe area.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        _calibrated ? Icons.check_circle : Icons.info_outline,
                        size: 16,
                        color: _calibrated
                            ? Theme.of(context).extension<AppColors>()!.success
                            : colors.outline,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _calibrated ? 'Calibrated' : 'Not calibrated',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Emergency stop
          FilledButton.icon(
            onPressed: _enabled
                ? () {
                    setState(() => _enabled = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Emergency stop activated')),
                    );
                  }
                : null,
            icon: const Icon(Icons.emergency),
            label: const Text('Emergency Stop'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Requires mobility hardware extension (2x N20 motors + cliff sensors).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
