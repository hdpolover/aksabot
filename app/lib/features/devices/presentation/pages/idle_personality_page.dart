import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../domain/entities/device_entity.dart';
import '../../domain/repositories/devices_repository.dart';

/// Idle personality settings — controls idle chat and animation frequency.
/// Persisted via PATCH /devices/:id/settings (one key at a time).
class IdlePersonalityPage extends StatefulWidget {
  final String deviceId;
  const IdlePersonalityPage({super.key, required this.deviceId});

  @override
  State<IdlePersonalityPage> createState() => _IdlePersonalityPageState();
}

class _IdlePersonalityPageState extends State<IdlePersonalityPage> {
  final _devicesRepo = sl<DevicesRepository>();

  bool _loading = true;
  String? _error;

  bool _idleChatEnabled = true;
  String _idleChatFrequency = 'normal';
  String _idleAnimationSpeed = 'normal';

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
      (device) {
        final s = device.settingsJson;
        setState(() {
          _idleChatEnabled = s['idle_chat_enabled'] as bool? ?? true;
          _idleChatFrequency =
              s['idle_chat_frequency'] as String? ?? 'normal';
          _idleAnimationSpeed =
              s['idle_animation_speed'] as String? ?? 'normal';
          _loading = false;
        });
      },
    );
  }

  int _pendingSaves = 0;

  Future<void> _save(String key, dynamic value) async {
    setState(() => _pendingSaves++);

    final result =
        await _devicesRepo.updateSettings(widget.deviceId, {key: value});
    if (!mounted) return;

    setState(() => _pendingSaves--);

    result.fold(
      (failure) {
        // Revert only the failed key by reloading from server
        _loadSettings();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: ${failure.message}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      },
      (_) {
        // Success — local state is already correct from the optimistic
        // setState in the onChanged callback. No need to overwrite other
        // fields from the server response.
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
                      Icon(Icons.error_outline, size: 48, color: colors.error),
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
              : ListView(
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
                            onChanged: _pendingSaves > 0
                                ? null
                                : (v) {
                                    setState(() => _idleChatEnabled = v);
                                    _save('idle_chat_enabled', v);
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
                                    child: Text(
                                      'Frequency',
                                      style: theme.textTheme.bodyLarge,
                                    ),
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
                                    onChanged: _pendingSaves > 0
                                        ? null
                                        : (v) {
                                            if (v == null) return;
                                            setState(
                                                () => _idleChatFrequency = v);
                                            _save('idle_chat_frequency', v);
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
                              child: Text(
                                'Animation speed',
                                style: theme.textTheme.bodyLarge,
                              ),
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
                              onChanged: _pendingSaves > 0
                                  ? null
                                  : (v) {
                                      if (v == null) return;
                                      setState(
                                          () => _idleAnimationSpeed = v);
                                      _save('idle_animation_speed', v);
                                    },
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (_pendingSaves > 0) ...[
                      const SizedBox(height: 16),
                      const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}
