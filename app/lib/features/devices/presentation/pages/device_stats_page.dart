import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../../scheduler/domain/repositories/scheduler_repository.dart';
import '../../domain/repositories/devices_repository.dart';

/// Stats & Diagnostics — usage stats, connection test, audio pipeline,
/// device logs, and factory reset. Merged from the former DeviceStatsPage
/// and DiagnosticsPage which duplicated the same stats data.
class DeviceStatsPage extends StatefulWidget {
  final String deviceId;
  const DeviceStatsPage({super.key, required this.deviceId});

  @override
  State<DeviceStatsPage> createState() => _DeviceStatsPageState();
}

class _DeviceStatsPageState extends State<DeviceStatsPage> {
  late final DevicesRepository _devicesRepo;
  late final SchedulerRepository _schedulerRepo;
  late final ApiClient _apiClient;

  // Usage stats
  bool _isLoading = true;
  String? _error;
  int _conversationsToday = 0;
  int _totalConversations = 0;
  int _totalMemories = 0;
  int _poolSize = 0;
  bool _isRefilling = false;

  // Connection test
  bool _testing = false;
  Map<String, _TestResult>? _testResults;

  @override
  void initState() {
    super.initState();
    _devicesRepo = sl<DevicesRepository>();
    _schedulerRepo = sl<SchedulerRepository>();
    _apiClient = sl<ApiClient>();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _devicesRepo.getStats(widget.deviceId);
    if (!mounted) return;

    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _isLoading = false;
      }),
      (stats) => setState(() {
        final s = stats;
        _conversationsToday = s['conversationsToday'] as int? ?? 0;
        _totalConversations = s['totalConversations'] as int? ?? 0;
        _totalMemories = s['totalMemories'] as int? ?? 0;
        _poolSize = s['poolSize'] as int? ?? 0;
        _isLoading = false;
      }),
    );
  }

  Future<void> _refillPool() async {
    setState(() => _isRefilling = true);
    final result = await _schedulerRepo.refillPool(widget.deviceId);
    result.fold(
      (failure) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refill failed: ${failure.message}')),
        );
      },
      (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pool refill triggered')),
        );
        _loadAll();
      },
    );
    if (mounted) setState(() => _isRefilling = false);
  }

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _testResults = null;
    });

    final sw = Stopwatch()..start();
    final apiResult = await _checkBackendApi(sw);
    final deviceResult = await _checkDeviceOnline();

    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResults = {
        'Backend API': apiResult,
        'WebSocket (lastSeen)': deviceResult,
      };
    });
  }

  Future<_TestResult> _checkBackendApi(Stopwatch sw) async {
    try {
      sw.reset();
      await _apiClient.get('/auth/me');
      return _TestResult(true, '${sw.elapsedMilliseconds}ms');
    } catch (_) {
      return const _TestResult(false, 'unreachable');
    }
  }

  Future<_TestResult> _checkDeviceOnline() async {
    final result = await _devicesRepo.getDevice(widget.deviceId);
    return result.fold(
      (_) => const _TestResult(false, 'fetch failed'),
      (device) {
        if (device.lastSeenAt == null) return const _TestResult(false, 'never seen');
        final diff = DateTime.now().difference(device.lastSeenAt!);
        final ago = _formatAgo(diff);
        return device.isOnline
            ? _TestResult(true, 'online ($ago)')
            : _TestResult(false, 'offline ($ago ago)');
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
      appBar: AppBar(title: const Text('Stats & Diagnostics')),
      body: _isLoading
          ? const AppLoadingIndicator()
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: TextStyle(color: colors.error)),
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        onPressed: _loadAll,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      // ── Usage ──────────────────────────────────────────
                      Text('Usage', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              value: '$_conversationsToday',
                              label: 'Today',
                              icon: Icons.chat_bubble_outline_rounded,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              value: '$_totalConversations',
                              label: 'All time',
                              icon: Icons.history_rounded,
                              color: colors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              value: '$_totalMemories',
                              label: 'Memories',
                              icon: Icons.psychology_rounded,
                              color: colors.tertiary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              value: '$_poolSize',
                              label: 'Pool entries',
                              icon: Icons.inventory_2_outlined,
                              color: colors.tertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          title: const Text('Response pool'),
                          subtitle: Text(
                            'Pre-generated bot messages — refill adds more',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          trailing: FilledButton.tonal(
                            onPressed: _isRefilling ? null : _refillPool,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: Text(_isRefilling ? 'Refilling...' : 'Refill'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Connection Test ────────────────────────────────
                      Text('Connection Test', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_testResults != null)
                                ..._testResults!.entries.map(
                                  (e) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Icon(
                                          e.value.passed
                                              ? Icons.check_circle
                                              : Icons.cancel,
                                          color: e.value.passed
                                              ? Theme.of(context)
                                                  .extension<AppColors>()!
                                                  .success
                                              : colors.error,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(child: Text(e.key)),
                                        Text(
                                          e.value.detail,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              FilledButton.tonal(
                                onPressed: _testing ? null : _runTest,
                                child: Text(_testing ? 'Testing...' : 'Run Test'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Audio Pipeline ─────────────────────────────────
                      Text('Audio Pipeline', style: theme.textTheme.titleMedium),
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
                                        'Audio pipeline test not yet implemented',
                                      ),
                                    ),
                                  );
                                },
                                child: const Text(
                                  'Test Mic \u2192 STT \u2192 LLM \u2192 TTS \u2192 Speaker',
                                ),
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

                      // ── Device Logs ────────────────────────────────────
                      Text('Device Logs', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Card(
                        child: Container(
                          height: 160,
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
                            const SnackBar(
                              content: Text('Log export not yet implemented'),
                            ),
                          );
                        },
                        child: const Text('Export Logs'),
                      ),
                      const SizedBox(height: 32),

                      // ── Danger Zone ────────────────────────────────────
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
                  content: Text('Factory reset not yet implemented'),
                ),
              );
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestResult {
  final bool passed;
  final String detail;
  const _TestResult(this.passed, this.detail);
}
