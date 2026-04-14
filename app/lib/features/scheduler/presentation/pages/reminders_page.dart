import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/reminder_config_entity.dart';
import '../bloc/scheduler_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';

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
            if (state is SchedulerLoading) return const AppLoadingIndicator();
            if (state is SchedulerError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.message,
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: () =>
                          context.read<SchedulerBloc>().add(LoadReminderConfig(deviceId)),
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

// ── Content ───────────────────────────────────────────────────────────────────

class _RemindersContent extends StatelessWidget {
  final ReminderConfig config;
  final bool isSaving;
  final String deviceId;

  const _RemindersContent({
    required this.config,
    required this.isSaving,
    required this.deviceId,
  });

  void _patch(BuildContext context, Map<String, dynamic> patch) {
    context.read<SchedulerBloc>().add(UpdateReminderConfig(deviceId, patch));
  }

  void _onToggle(BuildContext context, String key, bool enabled) {
    final entry = config.entries.firstWhere((e) => e.key == _label(key));
    _patch(context, {
      key: {'enabled': enabled, 'intervalMinutes': entry.value.intervalMinutes},
    });
  }

  void _onInterval(BuildContext context, String key, int minutes) {
    final entry = config.entries.firstWhere((e) => e.key == _label(key));
    _patch(context, {
      key: {'enabled': entry.value.enabled, 'intervalMinutes': minutes},
    });
  }

  String _label(String jsonKey) => switch (jsonKey) {
        'standUp'   => 'Stand Up',
        'hydration' => 'Hydration',
        'eyeBreak'  => 'Eye Break',
        'stretch'   => 'Stretch',
        'posture'   => 'Posture',
        _           => jsonKey,
      };

  String _jsonKey(String label) => switch (label) {
        'Stand Up'  => 'standUp',
        'Hydration' => 'hydration',
        'Eye Break' => 'eyeBreak',
        'Stretch'   => 'stretch',
        'Posture'   => 'posture',
        _           => label.toLowerCase(),
      };

  Future<void> _pickHour(BuildContext context, bool isStart) async {
    final initial = TimeOfDay(
      hour: isStart ? config.workHoursStart : config.workHoursEnd,
      minute: 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart ? 'Start of work hours' : 'End of work hours',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null && context.mounted) {
      _patch(context, {
        isStart ? 'workHoursStart' : 'workHoursEnd': picked.hour,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            // ── Schedule ───────────────────────────────────
            Text('Schedule', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Run all day'),
                    subtitle: Text(
                      config.allDay
                          ? 'Reminders fire any time of day'
                          : 'Reminders only fire during work hours',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    secondary: Icon(
                      config.allDay
                          ? Icons.all_inclusive_rounded
                          : Icons.schedule_rounded,
                      color: colors.primary,
                    ),
                    value: config.allDay,
                    onChanged: (v) => _patch(context, {'allDay': v}),
                  ),
                  if (!config.allDay) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _HourButton(
                              label: 'Start',
                              hour: config.workHoursStart,
                              onTap: () => _pickHour(context, true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _HourButton(
                              label: 'End',
                              hour: config.workHoursEnd,
                              onTap: () => _pickHour(context, false),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Health reminders ───────────────────────────
            Text('Health', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Periodic nudges to keep you moving and comfortable.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final entry in config.entries) ...[
                    if (entry != config.entries.first) const Divider(height: 1),
                    _ReminderRow(
                      label: entry.key,
                      item: entry.value,
                      onToggle: (v) => _onToggle(context, _jsonKey(entry.key), v),
                      onInterval: (m) => _onInterval(context, _jsonKey(entry.key), m),
                    ),
                  ],
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

// ── Hour picker button ────────────────────────────────────────────────────────

class _HourButton extends StatelessWidget {
  final String label;
  final int hour;
  final VoidCallback onTap;

  const _HourButton({
    required this.label,
    required this.hour,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatted = '${hour.toString().padLeft(2, '0')}:00';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonal(
            onPressed: onTap,
            child: Text(formatted),
          ),
        ),
      ],
    );
  }
}

// ── Reminder row ──────────────────────────────────────────────────────────────

class _ReminderRow extends StatelessWidget {
  final String label;
  final ReminderItem item;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onInterval;

  const _ReminderRow({
    required this.label,
    required this.item,
    required this.onToggle,
    required this.onInterval,
  });

  static const _intervals = [5, 10, 15, 20, 30, 45, 60, 90, 120];

  IconData get _icon => switch (label) {
        'Stand Up'  => Icons.accessibility_new_rounded,
        'Hydration' => Icons.water_drop_outlined,
        'Eye Break' => Icons.visibility_outlined,
        'Stretch'   => Icons.self_improvement_rounded,
        'Posture'   => Icons.airline_seat_recline_normal_rounded,
        _           => Icons.notifications_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final effectiveInterval =
        _intervals.contains(item.intervalMinutes) ? item.intervalMinutes : _intervals.first;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(_icon,
              color: item.enabled ? colors.primary : colors.onSurfaceVariant,
              size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: item.enabled ? null : colors.onSurfaceVariant,
                    )),
                Text(
                  'Every ${item.intervalMinutes}m',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          DropdownButton<int>(
            value: effectiveInterval,
            underline: const SizedBox.shrink(),
            style: theme.textTheme.bodyMedium,
            items: _intervals
                .map((m) => DropdownMenuItem(value: m, child: Text('${m}m')))
                .toList(),
            onChanged: item.enabled ? (v) { if (v != null) onInterval(v); } : null,
          ),
          const SizedBox(width: 4),
          Switch(value: item.enabled, onChanged: onToggle),
        ],
      ),
    );
  }
}
