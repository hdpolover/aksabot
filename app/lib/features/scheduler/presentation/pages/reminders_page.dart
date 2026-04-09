import 'package:flutter/material.dart';

import '../../domain/entities/reminder_config_entity.dart';
import '../../domain/repositories/scheduler_repository.dart';
import '../../../../core/di/injection.dart';

/// Page for toggling and configuring reminder intervals per type.
class RemindersPage extends StatefulWidget {
  final String deviceId;

  const RemindersPage({super.key, required this.deviceId});

  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  late final SchedulerRepository _repository;

  ReminderConfig? _config;
  bool _isLoading = true;
  String? _error;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _repository = sl<SchedulerRepository>();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _repository.getReminderConfig(widget.deviceId);
    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _isLoading = false;
      }),
      (config) => setState(() {
        _config = config;
        _isLoading = false;
      }),
    );
  }

  Future<void> _updateConfig(Map<String, dynamic> patch) async {
    setState(() => _isSaving = true);

    final result = await _repository.updateReminderConfig(
      widget.deviceId,
      patch,
    );

    result.fold(
      (failure) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: ${failure.message}')),
        );
      },
      (config) => setState(() => _config = config),
    );

    setState(() => _isSaving = false);
  }

  /// Builds the JSON key name from the display label.
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

  void _onToggle(String label, bool enabled) {
    final key = _jsonKey(label);
    final entry = _config!.entries.firstWhere((e) => e.key == label);
    _updateConfig({
      key: {
        'enabled': enabled,
        'intervalMinutes': entry.value.intervalMinutes,
      },
    });
  }

  void _onIntervalChanged(String label, int minutes) {
    final key = _jsonKey(label);
    final entry = _config!.entries.firstWhere((e) => e.key == label);
    _updateConfig({
      key: {
        'enabled': entry.value.enabled,
        'intervalMinutes': minutes,
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _loadConfig,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final config = _config;
    if (config == null) return const SizedBox.shrink();

    // Separate health vs daily reminders
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
            Text('Work Hours', style: Theme.of(context).textTheme.titleMedium),
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
                              Text('Start',
                                  style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 4),
                              FilledButton.tonal(
                                onPressed: () async {
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime:
                                        const TimeOfDay(hour: 8, minute: 0),
                                  );
                                  if (time != null) {
                                    _updateConfig({
                                      'workHoursStart':
                                          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                    });
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
                              Text('End',
                                  style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 4),
                              FilledButton.tonal(
                                onPressed: () async {
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime:
                                        const TimeOfDay(hour: 18, minute: 0),
                                  );
                                  if (time != null) {
                                    _updateConfig({
                                      'workHoursEnd':
                                          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                    });
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Health section
            Text('Health', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...healthEntries.map((entry) {
              return _ReminderTile(
                label: entry.key,
                item: entry.value,
                onToggle: (enabled) => _onToggle(entry.key, enabled),
                onIntervalChanged: (minutes) =>
                    _onIntervalChanged(entry.key, minutes),
              );
            }),
            const SizedBox(height: 24),

            // Daily section
            Text('Daily', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (dailyEntries.isNotEmpty)
              ...dailyEntries.map((entry) {
                return _ReminderTile(
                  label: entry.key,
                  item: entry.value,
                  onToggle: (enabled) => _onToggle(entry.key, enabled),
                  onIntervalChanged: (minutes) =>
                      _onIntervalChanged(entry.key, minutes),
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
        if (_isSaving)
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
            // Interval picker
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
