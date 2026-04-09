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

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: config.entries.map((entry) {
            return _ReminderTile(
              label: entry.key,
              item: entry.value,
              onToggle: (enabled) => _onToggle(entry.key, enabled),
              onIntervalChanged: (minutes) =>
                  _onIntervalChanged(entry.key, minutes),
            );
          }).toList(),
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
