import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../domain/entities/device_entity.dart';
import '../../domain/repositories/devices_repository.dart';

/// Voice & Audio settings — persisted via PATCH /devices/:id/settings.
class VoiceAudioPage extends StatefulWidget {
  final String deviceId;
  const VoiceAudioPage({super.key, required this.deviceId});

  @override
  State<VoiceAudioPage> createState() => _VoiceAudioPageState();
}

class _VoiceAudioPageState extends State<VoiceAudioPage> {
  final _devicesRepo = sl<DevicesRepository>();

  bool _loading = true;
  bool _saving = false;

  // Voice settings fields — mirror the keys stored in settingsJson.
  String _voicePreset = 'ziggy';
  double _speed = 0.8;
  double _stability = 0.6;
  bool _wakeSound = true;
  bool _sleepSound = true;
  bool _reminderChime = true;
  double _vadSensitivity = 0.5;


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
      _voicePreset = s['voice_preset'] as String? ?? 'ziggy';
      _speed = (s['voice_speed'] as num?)?.toDouble() ?? 0.8;
      _stability = (s['voice_stability'] as num?)?.toDouble() ?? 0.6;
      _wakeSound = s['audio_wake_sound'] as bool? ?? true;
      _sleepSound = s['audio_sleep_sound'] as bool? ?? true;
      _reminderChime = s['audio_reminder_chime'] as bool? ?? true;
      _vadSensitivity = (s['vad_sensitivity'] as num?)?.toDouble() ?? 0.5;
      _loading = false;
    });
  }

  /// Persist a single changed key without clobbering other settings.
  Future<void> _save(String key, dynamic value) async {
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
        appBar: AppBar(title: const Text('Voice & Audio')),
        body: const AppLoadingIndicator(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice & Audio'),
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
                  InputDecorator(
                    decoration: const InputDecoration(
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    ),
                    child: DropdownButton<String>(
                      value: _voicePreset,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(
                            value: 'ziggy',
                            child: Text('Ziggy (energetic boy)')),
                        DropdownMenuItem(
                            value: 'aria', child: Text('Aria (warm female)')),
                        DropdownMenuItem(
                            value: 'roger', child: Text('Roger (calm male)')),
                        DropdownMenuItem(
                            value: 'sarah', child: Text('Sarah (friendly)')),
                      ],
                      onChanged: _saving
                          ? null
                          : (v) {
                              if (v == null) return;
                              setState(() => _voicePreset = v);
                              _save('voice_preset', v);
                            },
                    ),
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
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _speed = v),
                          onChangeEnd: _saving
                              ? null
                              : (v) => _save('voice_speed', v),
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
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _stability = v),
                          onChangeEnd: _saving
                              ? null
                              : (v) => _save('voice_stability', v),
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
                  onChanged: _saving
                      ? null
                      : (v) {
                          setState(() => _wakeSound = v);
                          _save('audio_wake_sound', v);
                        },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Sleep sound'),
                  value: _sleepSound,
                  onChanged: _saving
                      ? null
                      : (v) {
                          setState(() => _sleepSound = v);
                          _save('audio_sleep_sound', v);
                        },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Reminder chime'),
                  value: _reminderChime,
                  onChanged: _saving
                      ? null
                      : (v) {
                          setState(() => _reminderChime = v);
                          _save('audio_reminder_chime', v);
                        },
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
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _vadSensitivity = v),
                          onChangeEnd: _saving
                              ? null
                              : (v) => _save('vad_sensitivity', v),
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
