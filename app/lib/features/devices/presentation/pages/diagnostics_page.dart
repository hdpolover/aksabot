import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/repositories/devices_repository.dart';

/// Diagnostics screen — real connectivity and device stats.
class DiagnosticsPage extends StatefulWidget {
  final String deviceId;
  const DiagnosticsPage({super.key, required this.deviceId});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  bool _testing = false;
  Map<String, _TestResult>? _results;
  Map<String, dynamic>? _stats;
  bool _loadingStats = true;

  final _devicesRepo = sl<DevicesRepository>();
  final _apiClient = sl<ApiClient>();

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loadingStats = true);
    final result = await _devicesRepo.getStats(widget.deviceId);
    if (!mounted) return;
    result.fold(
      (_) => setState(() => _loadingStats = false),
      (stats) => setState(() {
        _stats = stats;
        _loadingStats = false;
      }),
    );
  }

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _results = null;
    });

    // Run all checks concurrently.
    final stopwatch = Stopwatch()..start();
    final apiFuture = _checkBackendApi(stopwatch);
    final deviceFuture = _checkDeviceOnline();

    final apiResult = await apiFuture;
    final deviceResult = await deviceFuture;

    if (!mounted) return;
    setState(() {
      _testing = false;
      _results = {
        'Backend API': apiResult,
        'WebSocket (lastSeen)': deviceResult,
      };
    });
  }

  Future<_TestResult> _checkBackendApi(Stopwatch sw) async {
    try {
      sw.reset();
      // A lightweight authenticated endpoint — /auth/me is a good canary.
      await _apiClient.get('/auth/me');
      final ms = sw.elapsedMilliseconds;
      return _TestResult(true, '${ms}ms');
    } catch (_) {
      return _TestResult(false, 'unreachable');
    }
  }

  Future<_TestResult> _checkDeviceOnline() async {
    final result = await _devicesRepo.getDevice(widget.deviceId);
    return result.fold(
      (_) => _TestResult(false, 'fetch failed'),
      (device) {
        if (device.lastSeenAt == null) {
          return _TestResult(false, 'never seen');
        }
        final diff = DateTime.now().difference(device.lastSeenAt!);
        if (device.isOnline) {
          return _TestResult(true, 'online (${_formatAgo(diff)})');
        } else {
          return _TestResult(false, 'offline (${_formatAgo(diff)} ago)');
        }
      },
    );
  }

  String _formatAgo(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    return '${d.inHours}h';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Device stats
          Text('Device Stats', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _loadingStats
                  ? const AppLoadingIndicator()
                  : _stats == null
                      ? Text(
                          'Could not load stats',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.error,
                          ),
                        )
                      : Column(
                          children: [
                            _StatRow(
                              label: 'Conversations',
                              value: '${_stats!['conversations'] ?? 0}',
                              icon: Icons.chat_bubble_outline,
                              colors: colors,
                              theme: theme,
                            ),
                            const SizedBox(height: 8),
                            _StatRow(
                              label: 'Memories',
                              value: '${_stats!['memories'] ?? 0}',
                              icon: Icons.memory,
                              colors: colors,
                              theme: theme,
                            ),
                            const SizedBox(height: 8),
                            _StatRow(
                              label: 'Response pool',
                              value: '${_stats!['responsePool'] ?? 0}',
                              icon: Icons.queue,
                              colors: colors,
                              theme: theme,
                            ),
                          ],
                        ),
            ),
          ),
          const SizedBox(height: 24),

          // Connection test
          Text('Connection Test', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_results != null)
                    ...(_results!.entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              e.value.passed
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: e.value.passed
                                  ? Theme.of(context).extension<AppColors>()!.success
                                  : colors.error,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(e.key)),
                            Text(
                              e.value.detail,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: _testing ? null : _runTest,
                    child: Text(_testing ? 'Testing...' : 'Run Test'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Audio pipeline test
          Text('Audio Pipeline Test', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.tonal(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Audio pipeline test not yet implemented')),
                      );
                    },
                    child: const Text('Test Mic \u2192 STT \u2192 LLM \u2192 TTS \u2192 Speaker'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Last test: not run',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Device logs
          Text('Device Logs', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Container(
              height: 200,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  'Logs are streamed from the ESP32 over WebSocket.\n'
                  'Live log viewer requires Phase 5 firmware.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Log export not yet implemented')),
              );
            },
            child: const Text('Export Logs'),
          ),
          const SizedBox(height: 32),

          // Factory reset
          OutlinedButton.icon(
            onPressed: () => _confirmFactoryReset(context),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Factory Reset Device'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.error,
              side: BorderSide(color: colors.error),
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmFactoryReset(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Factory Reset'),
        content: const Text(
          'This will erase all device configuration, revoke its token, '
          'and remove it from your account. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Factory reset not yet implemented')),
              );
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final ColorScheme colors;
  final ThemeData theme;

  const _StatRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.colors,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: colors.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colors.primary,
          ),
        ),
      ],
    );
  }
}

class _TestResult {
  final bool passed;
  final String detail;
  const _TestResult(this.passed, this.detail);
}
