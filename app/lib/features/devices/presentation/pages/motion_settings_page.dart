import 'package:flutter/material.dart';

/// Servo & Motion settings — planned UI (future hardware extension).
class MotionSettingsPage extends StatefulWidget {
  final String deviceId;
  const MotionSettingsPage({super.key, required this.deviceId});

  @override
  State<MotionSettingsPage> createState() => _MotionSettingsPageState();
}

class _MotionSettingsPageState extends State<MotionSettingsPage> {
  bool _enabled = false;
  double _intensity = 0.5;
  bool _nodWhileListening = true;
  bool _lookAtUser = true;
  bool _reactToSpeech = true;
  bool _idleFidget = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Motion & Expression')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Enable toggle
          Card(
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              secondary: Icon(Icons.animation, color: colors.primary),
              title: const Text('Enable motion'),
              subtitle: const Text(
                'Aksa can move its head and body to express emotions while talking.',
              ),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
          ),
          const SizedBox(height: 24),

          // Intensity
          Text('Expression intensity', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text('Subtle', style: theme.textTheme.bodySmall),
                  Expanded(
                    child: Slider(
                      value: _intensity,
                      onChanged: _enabled
                          ? (v) => setState(() => _intensity = v)
                          : null,
                    ),
                  ),
                  Text('Expressive', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Behaviors
          Text('Behaviors', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Nod while listening'),
                  value: _nodWhileListening,
                  onChanged: _enabled
                      ? (v) => setState(() => _nodWhileListening = v)
                      : null,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Look at user'),
                  value: _lookAtUser,
                  onChanged: _enabled
                      ? (v) => setState(() => _lookAtUser = v)
                      : null,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('React to speech'),
                  value: _reactToSpeech,
                  onChanged: _enabled
                      ? (v) => setState(() => _reactToSpeech = v)
                      : null,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Idle fidget'),
                  value: _idleFidget,
                  onChanged: _enabled
                      ? (v) => setState(() => _idleFidget = v)
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Calibration
          Text('Calibration', style: theme.textTheme.titleMedium),
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
                                      'Calibration requires hardware')),
                            );
                          }
                        : null,
                    child: const Text('Calibrate Center'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sets the resting position for the servos.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Requires servo hardware extension (2x SG90).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
