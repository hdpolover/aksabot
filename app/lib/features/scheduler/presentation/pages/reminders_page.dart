import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/reminder_config_entity.dart';
import '../bloc/scheduler_bloc.dart';
import '../../../../core/di/injection.dart';

/// Page for toggling and configuring reminder intervals per type.
class RemindersPage extends StatelessWidget {
  final String deviceId;

  const RemindersPage({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<SchedulerBloc>()..add(LoadReminderConfig(deviceId)),
      child: Scaffold(
        appBar: AppBar(title: const Text('Reminders')),
        body: BlocBuilder<SchedulerBloc, SchedulerState>(
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
                      onPressed: () => context.read<SchedulerBloc>().add(LoadReminderConfig(deviceId)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }
            if (state is ReminderConfigLoaded) {
              return _RemindersContent(
                config: state.config,
                isSaving: state.isSaving,
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

class _RemindersContent extends StatelessWidget {
  final ReminderConfig config;
  final bool isSaving;
  final String deviceId;

  const _RemindersContent({
    required this.config,
    required this.isSaving,
    required this.deviceId,
  });

  String _jsonKey(String label) {
    switch (label) {
      case 'Stand Up':
        return 'standUp';
      case 'Hydration':
        return 'hydration';
      case 'Eye Break':
        return 'eyeBreak';
      case 'Stretch':
        return 'stretch';
      case 'Posture':
        return 'posture';
      default:
        return label.toLowerCase();
    }
  }

  void _onToggle(BuildContext context, String label, bool enabled) {
    final key = _jsonKey(label);
    final entry = config.entries.firstWhere((e) => e.key == label);
    context.read<SchedulerBloc>().add(UpdateReminderConfig(deviceId, {
      key: {
        'enabled': enabled,
        'intervalMinutes': entry.value.intervalMinutes,
      },
    }));
  }

  void _onIntervalChanged(BuildContext context, String label, int minutes) {
    final key = _jsonKey(label);
    final entry = config.entries.firstWhere((e) => e.key == label);
    context.read<SchedulerBloc>().add(UpdateReminderConfig(deviceId, {
      key: {
        'enabled': entry.value.enabled,
        'intervalMinutes': minutes,
      },
    }));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const healthKeys = ['Stand Up', 'Hydration', 'Eye Break', 'Stretch', 'Posture'];
    final healthEntries = config.entries
        .where((e) => healthKeys.contains(e.key))
        .toList();
    final dailyEntries = config.entries
        .where((e) => !healthKeys.contains(e.key))
        .toList();

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Work Hours card
            Text('Work Hours', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Start', style: theme.textTheme.bodySmall),
                              const SizedBox(height: 4),
                              FilledButton.tonal(
                                onPressed: () async {
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime: const TimeOfDay(hour: 8, minute: 0),
                                  );
                                  if (time != null && context.mounted) {
                                    context.read<SchedulerBloc>().add(
                                      UpdateReminderConfig(deviceId, {
                                        'workHoursStart':
                                            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                      }),
                                    );
                                  }
                                },
                                child: const Text('08:00'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('End', style: theme.textTheme.bodySmall),
                              const SizedBox(height: 4),
                              FilledButton.tonal(
                                onPressed: () async {
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime: const TimeOfDay(hour: 18, minute: 0),
                                  );
                                  if (time != null && context.mounted) {
                                    context.read<SchedulerBloc>().add(
                                      UpdateReminderConfig(deviceId, {
                                        'workHoursEnd':
                                            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                      }),
                                    );
                                  }
                                },
                                child: const Text('18:00'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Reminders only fire during work hours.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Health section
            Text('Health', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...healthEntries.map((entry) {
              return _ReminderTile(
                label: entry.key,
                item: entry.value,
                onToggle: (enabled) => _onToggle(context, entry.key, enabled),
                onIntervalChanged: (minutes) =>
                    _onIntervalChanged(context, entry.key, minutes),
              );
            }),
            const SizedBox(height: 24),

            // Daily section
            Text('Daily', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (dailyEntries.isNotEmpty)
              ...dailyEntries.map((entry) {
                return _ReminderTile(
                  label: entry.key,
                  item: entry.value,
                  onToggle: (enabled) => _onToggle(context, entry.key, enabled),
                  onIntervalChanged: (minutes) =>
                      _onIntervalChanged(context, entry.key, minutes),
                );
              })
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _DailyToggleTile(
                      icon: Icons.wb_sunny_outlined,
                      label: 'Morning briefing',
                      enabled: true,
                      onChanged: (_) {},
                    ),
                    const Divider(height: 1),
                    _DailyToggleTile(
                      icon: Icons.nightlight_outlined,
                      label: 'End of day',
                      subtitle: '18:00',
                      enabled: true,
                      onChanged: (_) {},
                    ),
                    const Divider(height: 1),
                    _DailyToggleTile(
                      icon: Icons.snooze,
                      label: 'Idle nudge',
                      subtitle: 'After 3 hours',
                      enabled: false,
                      onChanged: (_) {},
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (isSaving)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}

class _DailyToggleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _DailyToggleTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SwitchListTile(
      secondary: Icon(icon, color: theme.colorScheme.primary),
      title: Text(label),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      value: enabled,
      onChanged: onChanged,
    );
  }
}

class _ReminderTile extends StatelessWidget {
  final String label;
  final ReminderItem item;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onIntervalChanged;

  const _ReminderTile({
    required this.label,
    required this.item,
    required this.onToggle,
    required this.onIntervalChanged,
  });

  static const _intervalOptions = [5, 10, 15, 20, 30, 45, 60, 90, 120];

  IconData get _icon {
    switch (label) {
      case 'Stand Up':
        return Icons.accessibility_new;
      case 'Hydration':
        return Icons.water_drop_outlined;
      case 'Eye Break':
        return Icons.visibility_outlined;
      case 'Stretch':
        return Icons.self_improvement;
      case 'Posture':
        return Icons.airline_seat_recline_normal;
      default:
        return Icons.notifications_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(_icon, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Every ${item.intervalMinutes} min',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            DropdownButton<int>(
              value: _intervalOptions.contains(item.intervalMinutes)
                  ? item.intervalMinutes
                  : _intervalOptions.first,
              underline: const SizedBox.shrink(),
              items: _intervalOptions
                  .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text('${m}m'),
                      ))
                  .toList(),
              onChanged: item.enabled
                  ? (value) {
                      if (value != null) onIntervalChanged(value);
                    }
                  : null,
            ),
            const SizedBox(width: 8),
            Switch(
              value: item.enabled,
              onChanged: onToggle,
            ),
          ],
        ),
      ),
    );
  }
}
