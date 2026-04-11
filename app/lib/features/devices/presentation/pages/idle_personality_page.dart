import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../domain/entities/device_entity.dart';
import '../../domain/repositories/devices_repository.dart';

/// Idle personality settings — controls idle chat and animation frequency.
/// Persisted via PATCH /devices/:id/settings.
class IdlePersonalityPage extends StatefulWidget {
  final String deviceId;
  const IdlePersonalityPage({super.key, required this.deviceId});

  @override
  State<IdlePersonalityPage> createState() => _IdlePersonalityPageState();
}

class _IdlePersonalityPageState extends State<IdlePersonalityPage> {
  final _devicesRepo = sl<DevicesRepository>();

  bool _loading = true;
  bool _saving = false;

  // Idle chat settings
  bool _idleChatEnabled = true;
  String _idleChatFrequency = 'normal';

  // Idle animation speed
  String _idleAnimationSpeed = 'normal';

  // Full settings snapshot so we don't clobber unrelated keys on PATCH.
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
      _idleChatEnabled = s['idle_chat_enabled'] as bool? ?? true;
      _idleChatFrequency =
          s['idle_chat_frequency'] as String? ?? 'normal';
      _idleAnimationSpeed =
          s['idle_animation_speed'] as String? ?? 'normal';
      _loading = false;
    });
  }

  Future<void> _save(String key, dynamic value) async {
    if (_saving) return;
    setState(() => _saving = true);

    final patch = Map<String, dynamic>.from(_rawSettings)..[key] = value;
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

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Personality')),
        body: const AppLoadingIndicator(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personality'),
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
          // Idle chat section
          Text('Idle Chat', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Aksabot will randomly say fun things when idle.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Chat when idle'),
                  subtitle: const Text(
                    'Random fun facts, thoughts, and roasts',
                  ),
                  value: _idleChatEnabled,
                  onChanged: _saving
                      ? null
                      : (v) {
                          setState(() => _idleChatEnabled = v);
                          _save('idle_chat_enabled', v);
                        },
                ),
                if (_idleChatEnabled) ...[
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('Frequency'),
                    trailing: SizedBox(
                      width: 140,
                      child: DropdownButton<String>(
                        value: _idleChatFrequency,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(
                            value: 'rare',
                            child: Text('Rare (15-25 min)'),
                          ),
                          DropdownMenuItem(
                            value: 'normal',
                            child: Text('Normal (8-15 min)'),
                          ),
                          DropdownMenuItem(
                            value: 'frequent',
                            child: Text('Often (3-8 min)'),
                          ),
                        ],
                        onChanged: _saving
                            ? null
                            : (v) {
                                if (v == null) return;
                                setState(() => _idleChatFrequency = v);
                                _save('idle_chat_frequency', v);
                              },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Idle animation section
          Text('Idle Animations', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'How often the face does micro-animations when idle.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              title: const Text('Animation speed'),
              trailing: SizedBox(
                width: 140,
                child: DropdownButton<String>(
                  value: _idleAnimationSpeed,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                      value: 'slow',
                      child: Text('Slow (15-30s)'),
                    ),
                    DropdownMenuItem(
                      value: 'normal',
                      child: Text('Normal (8-20s)'),
                    ),
                    DropdownMenuItem(
                      value: 'fast',
                      child: Text('Fast (3-10s)'),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() => _idleAnimationSpeed = v);
                          _save('idle_animation_speed', v);
                        },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
