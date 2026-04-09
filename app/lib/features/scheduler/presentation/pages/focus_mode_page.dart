import 'package:flutter/material.dart';

import '../../domain/repositories/scheduler_repository.dart';
import '../../../../core/di/injection.dart';

/// Focus Mode screen — wired to backend POST/DELETE /devices/:id/focus.
class FocusModePage extends StatefulWidget {
  final String deviceId;
  const FocusModePage({super.key, required this.deviceId});

  @override
  State<FocusModePage> createState() => _FocusModePageState();
}

class _FocusModePageState extends State<FocusModePage> {
  late final SchedulerRepository _repository;

  bool _isActive = false;
  bool _isLoading = false;
  bool _pauseReminders = true;
  bool _silenceNudges = true;
  bool _allowPomodoro = true;
  bool _dimDisplay = false;
  String _autoEnd = 'off';

  @override
  void initState() {
    super.initState();
    _repository = sl<SchedulerRepository>();
  }

  int? get _durationMinutes {
    switch (_autoEnd) {
      case '1h':
        return 60;
      case '2h':
        return 120;
      case '4h':
        return 240;
      default:
        return null;
    }
  }

  Future<void> _startFocus() async {
    setState(() => _isLoading = true);
    final result = await _repository.startFocusMode(
      widget.deviceId,
      durationMinutes: _durationMinutes,
    );
    result.fold(
      (failure) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${failure.message}')),
        );
      },
      (_) => setState(() => _isActive = true),
    );
    setState(() => _isLoading = false);
  }

  Future<void> _stopFocus() async {
    setState(() => _isLoading = true);
    final result = await _repository.stopFocusMode(widget.deviceId);
    result.fold(
      (failure) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${failure.message}')),
        );
      },
      (_) => setState(() => _isActive = false),
    );
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Focus Mode')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Active state hero card
          if (_isActive) ...[
            Card(
              color: colors.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.center_focus_strong,
                        size: 48, color: colors.onPrimaryContainer),
                    const SizedBox(height: 12),
                    Text(
                      'FOCUSING',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Deep work session',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Reminders: paused',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onPrimaryContainer.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _stopFocus,
              icon: const Icon(Icons.stop),
              label: Text(_isLoading ? 'Stopping...' : 'End Focus Mode'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.error,
                side: BorderSide(color: colors.error),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ] else ...[
            Card(
              clipBehavior: Clip.antiAlias,
              child: SwitchListTile(
                secondary:
                    Icon(Icons.center_focus_strong, color: colors.primary),
                title: const Text('Enable Focus Mode'),
                subtitle: const Text(
                  'Pauses non-essential interruptions so you can concentrate.',
                ),
                value: _isActive,
                onChanged: _isLoading ? null : (v) {
                  if (v) _startFocus();
                },
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Behavior settings
          Text('Behavior during focus', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Pause reminders'),
                  value: _pauseReminders,
                  onChanged: (v) => setState(() => _pauseReminders = v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Silence nudges'),
                  value: _silenceNudges,
                  onChanged: (v) => setState(() => _silenceNudges = v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Allow pomodoro'),
                  value: _allowPomodoro,
                  onChanged: (v) => setState(() => _allowPomodoro = v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Dim display'),
                  value: _dimDisplay,
                  onChanged: (v) => setState(() => _dimDisplay = v),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Auto-end after'),
                  trailing: DropdownButton<String>(
                    value: _autoEnd,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'off', child: Text('Off')),
                      DropdownMenuItem(value: '1h', child: Text('1 hour')),
                      DropdownMenuItem(value: '2h', child: Text('2 hours')),
                      DropdownMenuItem(value: '4h', child: Text('4 hours')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _autoEnd = v);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'When focus ends, Aksa gives you a summary of what you missed.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
