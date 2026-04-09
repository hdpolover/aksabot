import 'package:flutter/material.dart';

import '../../domain/entities/pomodoro_entity.dart';
import '../../domain/repositories/scheduler_repository.dart';
import '../../../../core/di/injection.dart';

/// Page showing the current Pomodoro status with start/stop controls.
class PomodoroPage extends StatefulWidget {
  final String deviceId;

  const PomodoroPage({super.key, required this.deviceId});

  @override
  State<PomodoroPage> createState() => _PomodoroPageState();
}

class _PomodoroPageState extends State<PomodoroPage> {
  late final SchedulerRepository _repository;

  PomodoroStatus? _status;
  bool _isLoading = true;
  bool _isActing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = sl<SchedulerRepository>();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _repository.getPomodoroStatus(widget.deviceId);
    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _isLoading = false;
      }),
      (status) => setState(() {
        _status = status;
        _isLoading = false;
      }),
    );
  }

  Future<void> _start() async {
    setState(() => _isActing = true);

    final result = await _repository.startPomodoro(widget.deviceId);
    result.fold(
      (failure) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start: ${failure.message}')),
        );
      },
      (status) => setState(() => _status = status),
    );

    setState(() => _isActing = false);
  }

  Future<void> _stop() async {
    setState(() => _isActing = true);

    final result = await _repository.stopPomodoro(widget.deviceId);
    result.fold(
      (failure) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to stop: ${failure.message}')),
        );
      },
      (_) => setState(() => _status = const PomodoroStatus(active: false)),
    );

    setState(() => _isActing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pomodoro')),
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
              onPressed: _loadStatus,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final status = _status;
    if (status == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isActive = status.active;

    return RefreshIndicator(
      onRefresh: _loadStatus,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Status card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    isActive ? Icons.timer : Icons.timer_off_outlined,
                    size: 64,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isActive ? 'Session Active' : 'Not Running',
                    style: theme.textTheme.headlineSmall,
                  ),
                  if (isActive && status.phase != null) ...[
                    const SizedBox(height: 8),
                    Chip(
                      label: Text(_phaseLabel(status.phase!)),
                      backgroundColor:
                          _phaseColor(status.phase!, theme).withValues(alpha: 0.15),
                    ),
                  ],
                  if (isActive && status.cycle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Cycle ${status.cycle}',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                  if (isActive && status.durationMinutes != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${status.durationMinutes} min',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Action button
          SizedBox(
            height: 48,
            child: isActive
                ? OutlinedButton.icon(
                    onPressed: _isActing ? null : _stop,
                    icon: const Icon(Icons.stop),
                    label: Text(_isActing ? 'Stopping...' : 'Stop Session'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: _isActing ? null : _start,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(_isActing ? 'Starting...' : 'Start Pomodoro'),
                  ),
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
