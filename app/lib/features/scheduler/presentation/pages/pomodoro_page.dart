import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/pomodoro_entity.dart';
import '../bloc/scheduler_bloc.dart';
import '../../../../core/di/injection.dart';

/// Page showing the current Pomodoro status with start/stop controls.
class PomodoroPage extends StatelessWidget {
  final String deviceId;

  const PomodoroPage({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<SchedulerBloc>()..add(LoadPomodoroStatus(deviceId)),
      child: Scaffold(
        appBar: AppBar(title: const Text('Pomodoro')),
        body: BlocConsumer<SchedulerBloc, SchedulerState>(
          listener: (context, state) {
            if (state is SchedulerError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message)),
              );
            }
          },
          builder: (context, state) {
            if (state is SchedulerLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is SchedulerError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: () => context.read<SchedulerBloc>().add(LoadPomodoroStatus(deviceId)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }
            if (state is PomodoroStatusLoaded) {
              return _PomodoroContent(
                status: state.status,
                isActing: state.isActing,
                deviceId: deviceId,
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

class _PomodoroContent extends StatelessWidget {
  final PomodoroStatus status;
  final bool isActing;
  final String deviceId;

  const _PomodoroContent({
    required this.status,
    required this.isActing,
    required this.deviceId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isActive = status.active;
    final phaseColor = isActive && status.phase != null
        ? _phaseColor(status.phase!, theme)
        : colors.outline;

    return RefreshIndicator(
      onRefresh: () async {
        context.read<SchedulerBloc>().add(LoadPomodoroStatus(deviceId));
      },
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Circular progress hero
          Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: CircularProgressIndicator(
                      value: isActive ? 0.65 : 0.0,
                      strokeWidth: 8,
                      backgroundColor: colors.surfaceContainerHighest,
                      color: phaseColor,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isActive
                            ? '${status.durationMinutes ?? 25}:00'
                            : '--:--',
                        style: theme.textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: phaseColor,
                        ),
                      ),
                      if (isActive && status.phase != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${_phaseLabel(status.phase!)}${status.cycle != null ? ' ${status.cycle}/4' : ''}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ] else
                        Text(
                          'Not Running',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Action buttons
          if (isActive)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isActing ? null : () {},
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Skip'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isActing
                        ? null
                        : () => context.read<SchedulerBloc>().add(StopPomodoro(deviceId)),
                    icon: const Icon(Icons.stop),
                    label: Text(isActing ? 'Stopping...' : 'Stop'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.error,
                      side: BorderSide(color: colors.error),
                    ),
                  ),
                ),
              ],
            )
          else
            FilledButton.icon(
              onPressed: isActing
                  ? null
                  : () => context.read<SchedulerBloc>().add(StartPomodoro(deviceId)),
              icon: const Icon(Icons.play_arrow),
              label: Text(isActing ? 'Starting...' : 'Start Pomodoro'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          const SizedBox(height: 24),

          // Settings (expandable)
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: Icon(Icons.tune, color: colors.onSurfaceVariant),
              title: const Text('Settings'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    children: [
                      _SettingRow(
                        label: 'Focus',
                        value: '25 min',
                        options: const ['15 min', '20 min', '25 min', '30 min'],
                        onChanged: (_) {},
                      ),
                      _SettingRow(
                        label: 'Short break',
                        value: '5 min',
                        options: const ['3 min', '5 min', '10 min'],
                        onChanged: (_) {},
                      ),
                      _SettingRow(
                        label: 'Long break',
                        value: '15 min',
                        options: const ['10 min', '15 min', '20 min'],
                        onChanged: (_) {},
                      ),
                      _SettingRow(
                        label: 'Cycles',
                        value: '4',
                        options: const ['3', '4', '5'],
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Daily stats
          Row(
            children: [
              Icon(Icons.emoji_events_outlined, size: 16, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Today: 0 focus sessions',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.schedule, size: 16, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Total focus time: 0m',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _phaseLabel(String phase) {
    switch (phase) {
      case 'work':
        return 'Focus';
      case 'short_break':
        return 'Short Break';
      case 'long_break':
        return 'Long Break';
      default:
        return phase;
    }
  }

  Color _phaseColor(String phase, ThemeData theme) {
    switch (phase) {
      case 'work':
        return theme.colorScheme.primary;
      case 'short_break':
        return theme.colorScheme.tertiary;
      case 'long_break':
        return theme.colorScheme.secondary;
      default:
        return theme.colorScheme.outline;
    }
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _SettingRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          DropdownButton<String>(
            value: value,
            underline: const SizedBox.shrink(),
            items: options
                .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}
