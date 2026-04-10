import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/scheduler_bloc.dart';
import '../../../../core/di/injection.dart';

/// Focus Mode screen — wired to backend POST/DELETE /devices/:id/focus.
class FocusModePage extends StatefulWidget {
  final String deviceId;
  const FocusModePage({super.key, required this.deviceId});

  @override
  State<FocusModePage> createState() => _FocusModePageState();
}

class _FocusModePageState extends State<FocusModePage> {
  bool _pauseReminders = true;
  bool _silenceNudges = true;
  bool _allowPomodoro = true;
  bool _dimDisplay = false;
  String _autoEnd = 'off';

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

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<SchedulerBloc>(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Focus Mode')),
        body: BlocConsumer<SchedulerBloc, SchedulerState>(
          listener: (context, state) {
            if (state is SchedulerError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed: ${state.message}')),
              );
            }
          },
          builder: (context, state) {
            final isActive = state is FocusModeActive;
            final isLoading = state is SchedulerLoading;

            return _buildBody(context, isActive: isActive, isLoading: isLoading);
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, {required bool isActive, required bool isLoading}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Active state hero card
        if (isActive) ...[
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
            onPressed: isLoading
                ? null
                : () => context.read<SchedulerBloc>().add(StopFocusMode(widget.deviceId)),
            icon: const Icon(Icons.stop),
            label: Text(isLoading ? 'Stopping...' : 'End Focus Mode'),
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
              secondary: Icon(Icons.center_focus_strong, color: colors.primary),
              title: const Text('Enable Focus Mode'),
              subtitle: const Text(
                'Pauses non-essential interruptions so you can concentrate.',
              ),
              value: isActive,
              onChanged: isLoading
                  ? null
                  : (v) {
                      if (v) {
                        context.read<SchedulerBloc>().add(
                          StartFocusMode(widget.deviceId, durationMinutes: _durationMinutes),
                        );
                      }
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
    );
  }
}
