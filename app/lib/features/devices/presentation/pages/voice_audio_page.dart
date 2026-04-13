import 'package:audioplayers/audioplayers.dart';
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
  final _audioPlayer = AudioPlayer();
  final _previewTextController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _previewing = false;
  bool _previewingOnDevice = false;
  PlayerState _playerState = PlayerState.stopped;

  bool _deviceOnline = false;

  // Voice settings fields — mirror the keys stored in settingsJson.
  String _voicePreset = 'ziggy';
  double _speed = 0.7;
  double _stability = 0.6;
  bool _wakeSound = true;
  bool _sleepSound = true;
  bool _reminderChime = true;
  double _vadSensitivity = 0.5;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _previewTextController.dispose();
    super.dispose();
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

  static const _validPresets = {'ziggy', 'little_dude', 'sean', 'nelson', 'nathan'};

  void _applySettings(Device device) {
    final s = device.settingsJson;
    final preset = s['voice_preset'] as String? ?? 'ziggy';
    setState(() {
      _voicePreset = _validPresets.contains(preset) ? preset : 'ziggy';
      _speed = (s['voice_speed'] as num?)?.toDouble() ?? 0.7;
      _stability = (s['voice_stability'] as num?)?.toDouble() ?? 0.6;
      _wakeSound = s['audio_wake_sound'] as bool? ?? true;
      _sleepSound = s['audio_sleep_sound'] as bool? ?? true;
      _reminderChime = s['audio_reminder_chime'] as bool? ?? true;
      _vadSensitivity = (s['vad_sensitivity'] as num?)?.toDouble() ?? 0.5;
      _deviceOnline = device.isOnline;
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

  Future<void> _pushPreviewToDevice() async {
    setState(() => _previewingOnDevice = true);

    final customText = _previewTextController.text.trim();
    final result = await _devicesRepo.pushVoicePreviewToDevice(
      widget.deviceId,
      voicePreset: _voicePreset,
      speed: _speed,
      stability: _stability,
      text: customText.isEmpty ? null : customText,
    );

    if (!mounted) return;
    setState(() => _previewingOnDevice = false);

    result.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${failure.message}')),
        );
      },
      (playing) {
        if (!playing) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device is busy or offline — try again shortly'),
            ),
          );
        }
      },
    );
  }

  Future<void> _togglePreview() async {
    // If already playing, stop it.
    if (_playerState == PlayerState.playing) {
      await _audioPlayer.stop();
      return;
    }

    setState(() => _previewing = true);

    final customText = _previewTextController.text.trim();
    final result = await _devicesRepo.previewVoice(
      widget.deviceId,
      voicePreset: _voicePreset,
      speed: _speed,
      stability: _stability,
      text: customText.isEmpty ? null : customText,
    );

    if (!mounted) return;
    setState(() => _previewing = false);

    result.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preview failed: ${failure.message}')),
        );
      },
      (audioBytes) async {
        await _audioPlayer.play(
          BytesSource(audioBytes, mimeType: 'audio/mpeg'),
        );
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

    final isPlaying = _playerState == PlayerState.playing;

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
          // ── Voice settings ──────────────────────────────────
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
                        DropdownMenuItem(value: 'ziggy',       child: Text('Ziggy')),
                        DropdownMenuItem(value: 'little_dude', child: Text('Little Dude')),
                        DropdownMenuItem(value: 'sean',        child: Text('Sean')),
                        DropdownMenuItem(value: 'nelson',      child: Text('Nelson')),
                        DropdownMenuItem(value: 'nathan',      child: Text('Nathan')),
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
                  const SizedBox(height: 16),
                  // ── Custom preview text ─────────────────────
                  TextField(
                    controller: _previewTextController,
                    maxLength: 300,
                    maxLines: 2,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: "What should Aksa say?",
                      helperText: 'Leave empty to use the default phrase',
                      counterStyle: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      suffixIcon: ListenableBuilder(
                        listenable: _previewTextController,
                        builder: (context, _) => _previewTextController.text.isEmpty
                            ? const SizedBox.shrink()
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: _previewTextController.clear,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // ── Preview buttons ─────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: (_saving || _previewing || _previewingOnDevice) ? null : _togglePreview,
                      child: _previewing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isPlaying
                                      ? Icons.stop_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 20,
                                ),
                                const SizedBox(width: 6),
                                Text(isPlaying ? 'Stop' : 'Preview voice'),
                              ],
                            ),
                    ),
                  ),
                  if (_deviceOnline) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: (_saving || _previewing || _previewingOnDevice)
                            ? null
                            : _pushPreviewToDevice,
                        child: _previewingOnDevice
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.speaker_rounded, size: 20),
                                  SizedBox(width: 6),
                                  Text('Play on device'),
                                ],
                              ),
                      ),
                    ),
                  ],
                  if (isPlaying) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Playing Aksa\'s voice...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Audio toggles ────────────────────────────────────
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

          // ── Advanced (VAD) ───────────────────────────────────
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
