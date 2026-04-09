import 'package:flutter/material.dart';

/// Presence detection settings — planned UI.
class PresenceSettingsPage extends StatefulWidget {
  final String deviceId;
  const PresenceSettingsPage({super.key, required this.deviceId});

  @override
  State<PresenceSettingsPage> createState() => _PresenceSettingsPageState();
}

class _PresenceSettingsPageState extends State<PresenceSettingsPage> {
  bool _enabled = true;
  double _rssiThreshold = -75;
  String _gracePeriod = '45';
  String _silentWake = '5';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Presence Detection')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
              onChanged: (v) => setState(() => _enabled = v),
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
                        ? (v) => setState(() => _rssiThreshold = v)
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.signal_cellular_alt,
                          size: 16, color: colors.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(
                        'Current RSSI: -- dBm',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'BLE not connected',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.outline,
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
