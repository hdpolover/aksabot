import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../domain/entities/device_entity.dart';
import '../../domain/repositories/devices_repository.dart';

/// Idle personality settings — controls idle chat and animation frequency.
/// All changes are collected locally and saved together via a Save button.
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
  bool _dirty = false;
  String? _error;

  bool _idleChatEnabled = true;
  String _idleChatFrequency = 'normal';
  String _idleAnimationSpeed = 'normal';

  // Server values — used to detect changes
  bool _serverChatEnabled = true;
  String _serverChatFrequency = 'normal';
  String _serverAnimationSpeed = 'normal';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _devicesRepo.getDevice(widget.deviceId);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _loading = false;
      }),
      (device) => _applyFromServer(device),
    );
  }

  void _applyFromServer(Device device) {
    final s = device.settingsJson;
    final chatEnabled = s['idle_chat_enabled'] as bool? ?? true;
    final chatFreq = s['idle_chat_frequency'] as String? ?? 'normal';
    final animSpeed = s['idle_animation_speed'] as String? ?? 'normal';
    setState(() {
      _idleChatEnabled = chatEnabled;
      _idleChatFrequency = chatFreq;
      _idleAnimationSpeed = animSpeed;
      _serverChatEnabled = chatEnabled;
      _serverChatFrequency = chatFreq;
      _serverAnimationSpeed = animSpeed;
      _dirty = false;
      _loading = false;
    });
  }

  void _markDirty() {
    final isDirty = _idleChatEnabled != _serverChatEnabled ||
        _idleChatFrequency != _serverChatFrequency ||
        _idleAnimationSpeed != _serverAnimationSpeed;
    if (isDirty != _dirty) setState(() => _dirty = isDirty);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    // Only send keys that actually changed
    final patch = <String, dynamic>{};
    if (_idleChatEnabled != _serverChatEnabled) {
      patch['idle_chat_enabled'] = _idleChatEnabled;
    }
    if (_idleChatFrequency != _serverChatFrequency) {
      patch['idle_chat_frequency'] = _idleChatFrequency;
    }
    if (_idleAnimationSpeed != _serverAnimationSpeed) {
      patch['idle_animation_speed'] = _idleAnimationSpeed;
    }

    if (patch.isEmpty) {
      setState(() => _saving = false);
      return;
    }

    final result =
        await _devicesRepo.updateSettings(widget.deviceId, patch);
    if (!mounted) return;

    result.fold(
      (failure) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: ${failure.message}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      },
      (device) {
        _applyFromServer(device);
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved')),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Personality')),
      body: _loading
          ? const AppLoadingIndicator()
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: colors.error),
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: colors.error)),
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        onPressed: _loadSettings,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Idle chat section
                    Text('Idle Chat', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Aksa will randomly say fun things when idle.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
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
                            onChanged: (v) {
                              setState(() => _idleChatEnabled = v);
                              _markDirty();
                            },
                          ),
                          if (_idleChatEnabled) ...[
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text('Frequency',
                                        style: theme.textTheme.bodyLarge),
                                  ),
                                  DropdownButton<String>(
                                    value: _idleChatFrequency,
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
                                    onChanged: (v) {
                                      if (v == null) return;
                                      setState(
                                          () => _idleChatFrequency = v);
                                      _markDirty();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppConstants.spacingXxl),

                    // Idle animation section
                    Text('Idle Animations',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'How often the face does micro-animations when idle.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('Animation speed',
                                  style: theme.textTheme.bodyLarge),
                            ),
                            DropdownButton<String>(
                              value: _idleAnimationSpeed,
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
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => _idleAnimationSpeed = v);
                                _markDirty();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                    ),
                    // Sticky save bar
                    if (_dirty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Save'),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
