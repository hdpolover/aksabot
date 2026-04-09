import 'package:flutter/material.dart';

/// Voice & Audio settings — planned UI (Phase 5 for VAD).
class VoiceAudioPage extends StatefulWidget {
  final String deviceId;
  const VoiceAudioPage({super.key, required this.deviceId});

  @override
  State<VoiceAudioPage> createState() => _VoiceAudioPageState();
}

class _VoiceAudioPageState extends State<VoiceAudioPage> {
  String _voicePreset = 'ziggy';
  double _speed = 0.8;
  double _stability = 0.6;
  bool _wakeSound = true;
  bool _sleepSound = true;
  bool _reminderChime = true;
  double _vadSensitivity = 0.5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Voice & Audio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Voice settings
          Text('Voice', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Voice preset', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _voicePreset,
                    decoration: const InputDecoration(
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'ziggy', child: Text('Ziggy (energetic boy)')),
                      DropdownMenuItem(
                          value: 'aria', child: Text('Aria (warm female)')),
                      DropdownMenuItem(
                          value: 'roger', child: Text('Roger (calm male)')),
                      DropdownMenuItem(
                          value: 'sarah', child: Text('Sarah (friendly)')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _voicePreset = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('Speed', style: theme.textTheme.bodyMedium),
                  Row(
                    children: [
                      Text('Slower', style: theme.textTheme.bodySmall),
                      Expanded(
                        child: Slider(
                          value: _speed,
                          min: 0.5,
                          max: 1.5,
                          divisions: 10,
                          label: '${_speed.toStringAsFixed(1)}x',
                          onChanged: (v) => setState(() => _speed = v),
                        ),
                      ),
                      Text('Faster', style: theme.textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Stability', style: theme.textTheme.bodyMedium),
                  Row(
                    children: [
                      Text('Variable', style: theme.textTheme.bodySmall),
                      Expanded(
                        child: Slider(
                          value: _stability,
                          min: 0.0,
                          max: 1.0,
                          divisions: 10,
                          label: _stability.toStringAsFixed(1),
                          onChanged: (v) => setState(() => _stability = v),
                        ),
                      ),
                      Text('Stable', style: theme.textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Voice preview not yet implemented')),
                      );
                    },
                    child: const Text('Preview Voice'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Audio toggles
          Text('Audio', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Wake sound'),
                  value: _wakeSound,
                  onChanged: (v) => setState(() => _wakeSound = v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Sleep sound'),
                  value: _sleepSound,
                  onChanged: (v) => setState(() => _sleepSound = v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Reminder chime'),
                  value: _reminderChime,
                  onChanged: (v) => setState(() => _reminderChime = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // VAD
          Text('Advanced', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('VAD sensitivity', style: theme.textTheme.bodyMedium),
                  Row(
                    children: [
                      Text('Less', style: theme.textTheme.bodySmall),
                      Expanded(
                        child: Slider(
                          value: _vadSensitivity,
                          min: 0.0,
                          max: 1.0,
                          divisions: 10,
                          onChanged: (v) =>
                              setState(() => _vadSensitivity = v),
                        ),
                      ),
                      Text('More', style: theme.textTheme.bodySmall),
                    ],
                  ),
                  Text(
                    'VAD determines when you\'ve stopped talking. '
                    'Higher = more responsive, but may cut you off sooner.',
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
            'VAD requires Phase 5 firmware update.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
