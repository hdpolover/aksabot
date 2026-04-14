import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../../scheduler/domain/repositories/scheduler_repository.dart';
import '../../domain/repositories/devices_repository.dart';

/// Stats & Diagnostics — usage stats, connection test, audio pipeline,
/// device logs, and factory reset.
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
  List<_TestResult>? _testResults;

  // Device logs
  bool _fetchingLogs = false;
  DeviceLogs? _logs;

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
        _conversationsToday = stats['conversationsToday'] as int? ?? 0;
        _totalConversations = stats['totalConversations'] as int? ?? 0;
        _totalMemories = stats['totalMemories'] as int? ?? 0;
        _poolSize = stats['poolSize'] as int? ?? 0;
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
    final wsResult = await _checkWebSocket();

    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResults = [
        _TestResult(label: 'Backend API', result: apiResult),
        _TestResult(label: 'Device connection', result: deviceResult),
        _TestResult(label: 'WebSocket gateway', result: wsResult),
      ];
    });
  }

  Future<_CheckResult> _checkBackendApi(Stopwatch sw) async {
    try {
      sw.reset();
      await _apiClient.get('/auth/me');
      return _CheckResult(true, '${sw.elapsedMilliseconds}ms');
    } catch (_) {
      return const _CheckResult(false, 'unreachable');
    }
  }

  Future<_CheckResult> _checkDeviceOnline() async {
    final result = await _devicesRepo.getDevice(widget.deviceId);
    return result.fold(
      (_) => const _CheckResult(false, 'fetch failed'),
      (device) {
        if (device.lastSeenAt == null) return const _CheckResult(false, 'never seen');
        final diff = DateTime.now().difference(device.lastSeenAt!);
        final ago = _formatAgo(diff);
        return device.isOnline
            ? _CheckResult(true, 'online · seen $ago ago')
            : _CheckResult(false, 'offline · seen $ago ago');
      },
    );
  }

  Future<_CheckResult> _checkWebSocket() async {
    // Check if the device has an active WebSocket session by re-fetching device
    // and verifying it's online (backend marks online via active WS session).
    final result = await _devicesRepo.getDevice(widget.deviceId);
    return result.fold(
      (_) => const _CheckResult(false, 'could not verify'),
      (device) => device.isOnline
          ? const _CheckResult(true, 'session active')
          : const _CheckResult(false, 'no active session'),
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
                      _buildUsageSection(theme, colors),
                      const SizedBox(height: 24),
                      _buildConnectionSection(theme, colors),
                      const SizedBox(height: 24),
                      _buildAudioPipelineSection(theme, colors),
                      const SizedBox(height: 24),
                      _buildDeviceLogsSection(theme, colors),
                      const SizedBox(height: 32),
                      _buildDangerZone(colors),
                    ],
                  ),
                ),
    );
  }

  // ── Usage ──────────────────────────────────────────────────────────────────

  Widget _buildUsageSection(ThemeData theme, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            leading: Icon(
              Icons.auto_awesome_outlined,
              color: colors.tertiary,
              size: 20,
            ),
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Text(_isRefilling ? 'Refilling…' : 'Refill'),
            ),
          ),
        ),
      ],
    );
  }

  // ── Connection test ────────────────────────────────────────────────────────

  Widget _buildConnectionSection(ThemeData theme, ColorScheme colors) {
    final appColors = theme.extension<AppColors>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Connection Test', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_testResults != null) ...[
                  ..._testResults!.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Icon(
                            t.result.passed
                                ? Icons.check_circle_rounded
                                : Icons.cancel_rounded,
                            color: t.result.passed
                                ? appColors.success
                                : colors.error,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              t.label,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            t.result.detail,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: t.result.passed
                                  ? appColors.success
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 16),
                ],
                FilledButton.tonal(
                  onPressed: _testing ? null : _runTest,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                  ),
                  child: _testing
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _testResults != null ? 'Run Again' : 'Run Test',
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Audio pipeline ─────────────────────────────────────────────────────────

  Widget _buildAudioPipelineSection(ThemeData theme, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Audio Pipeline', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.mic_none_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Mic → STT → LLM → TTS → Speaker',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Full end-to-end test requires the device to be online. '
                          'Available once firmware is live.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                  ),
                  child: const Text('Test Pipeline'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _fetchLogs() async {
    setState(() => _fetchingLogs = true);
    final result = await _devicesRepo.fetchLogs(widget.deviceId);
    if (!mounted) return;
    result.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch logs: ${failure.message}')),
        );
      },
      (logs) => setState(() => _logs = logs),
    );
    setState(() => _fetchingLogs = false);
  }

  Future<void> _exportLogs() async {
    final text = _logs?.text;
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log text copied to clipboard')),
    );
  }

  // ── Device logs ────────────────────────────────────────────────────────────

  Widget _buildDeviceLogsSection(ThemeData theme, ColorScheme colors) {
    final hasLogs = _logs?.hasData == true;
    final logText = _logs?.text ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Device Logs', style: theme.textTheme.titleMedium),
            if (_logs?.fetchedAt != null) ...[
              const SizedBox(width: 8),
              Text(
                'fetched ${_formatAgo(DateTime.now().difference(_logs!.fetchedAt!))} ago',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 200,
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: hasLogs
                    ? Scrollbar(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            logText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: colors.onSurface,
                              height: 1.5,
                            ),
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.fiber_manual_record,
                                size: 8,
                                color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _fetchingLogs ? 'Requesting logs…' : 'No logs loaded',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          if (!_fetchingLogs) ...[
                            const SizedBox(height: 6),
                            Text(
                              '// Tap "Fetch Logs" to pull the last 6 KB\n'
                              '// of log data from the device over WebSocket.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: _fetchingLogs ? null : _fetchLogs,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 44),
                        ),
                        child: _fetchingLogs
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(hasLogs ? 'Refresh Logs' : 'Fetch Logs'),
                      ),
                    ),
                    if (hasLogs) ...[
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _exportLogs,
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        label: const Text('Copy'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Danger zone ────────────────────────────────────────────────────────────

  Widget _buildDangerZone(ColorScheme colors) {
    return OutlinedButton.icon(
      onPressed: () => _confirmFactoryReset(context),
      icon: const Icon(Icons.restart_alt_rounded),
      label: const Text('Factory Reset Device'),
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.error,
        side: BorderSide(color: colors.error),
        minimumSize: const Size(double.infinity, 48),
      ),
    );
  }

  Future<void> _performFactoryReset(BuildContext context) async {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Factory resetting device…'),
        duration: Duration(seconds: 3),
      ),
    );

    final result = await _devicesRepo.factoryReset(widget.deviceId);
    if (!context.mounted) return;

    result.fold(
      (failure) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Factory reset failed: ${failure.message}')),
        );
      },
      (_) {
        ScaffoldMessenger.of(context).clearSnackBars();
        context.go('/home');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device factory reset. Re-provision it from the app.'),
          ),
        );
      },
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
            onPressed: () async {
              Navigator.pop(ctx);
              await _performFactoryReset(context);
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

// ── Private widgets ────────────────────────────────────────────────────────

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
  final String label;
  final _CheckResult result;
  const _TestResult({required this.label, required this.result});
}

class _CheckResult {
  final bool passed;
  final String detail;
  const _CheckResult(this.passed, this.detail);
}
