import 'package:flutter/material.dart';

import '../../domain/entities/device_entity.dart';
import '../../domain/repositories/devices_repository.dart';
import '../../../scheduler/domain/repositories/scheduler_repository.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../../../core/widgets/status_dot.dart';

/// Device statistics screen — wired to GET /devices/:id/stats.
class DeviceStatsPage extends StatefulWidget {
  final String deviceId;
  const DeviceStatsPage({super.key, required this.deviceId});

  @override
  State<DeviceStatsPage> createState() => _DeviceStatsPageState();
}

class _DeviceStatsPageState extends State<DeviceStatsPage> {
  late final DevicesRepository _devicesRepo;
  late final SchedulerRepository _schedulerRepo;

  bool _isLoading = true;
  String? _error;

  Device? _device;

  int _conversationsToday = 0;
  int _totalConversations = 0;
  int _totalMemories = 0;
  int _poolSize = 0;

  bool _isRefilling = false;

  @override
  void initState() {
    super.initState();
    _devicesRepo = sl<DevicesRepository>();
    _schedulerRepo = sl<SchedulerRepository>();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Load device info and stats in parallel
    final results = await Future.wait([
      _devicesRepo.getDevice(widget.deviceId),
      _devicesRepo.getStats(widget.deviceId),
    ]);

    final deviceResult = results[0];
    final statsResult = results[1];

    // Device info — needed for System section
    deviceResult.fold(
      (_) => null, // best-effort, non-fatal
      (device) => _device = device as Device,
    );

    // Stats — if this fails, show error
    statsResult.fold(
      (failure) {
        setState(() {
          _error = failure.message;
          _isLoading = false;
        });
        return;
      },
      (stats) {
        setState(() {
          final s = stats as Map<String, dynamic>;
          _conversationsToday = s['conversationsToday'] as int? ?? 0;
          _totalConversations = s['totalConversations'] as int? ?? 0;
          _totalMemories = s['totalMemories'] as int? ?? 0;
          _poolSize = s['poolSize'] as int? ?? 0;
          _isLoading = false;
        });
      },
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Stats & History')),
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
                      // ── Conversations ──────────────────────────────────
                      Text('Conversations', style: theme.textTheme.titleMedium),
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
                      const SizedBox(height: 24),

                      // ── Memory & Pool ──────────────────────────────────
                      Text('Memory & Pool', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
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
                          trailing: SizedBox(
                            width: 90,
                            height: 36,
                            child: FilledButton.tonal(
                              onPressed: _isRefilling ? null : _refillPool,
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              child:
                                  Text(_isRefilling ? 'Refilling...' : 'Refill'),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Device ─────────────────────────────────────────
                      Text('Device', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            _buildStatusTile(theme, colors),
                            const Divider(height: 1),
                            _InfoTile(
                              label: 'Uptime',
                              value: _formatUptime(),
                            ),
                            const Divider(height: 1),
                            _InfoTile(
                              label: 'Wi-Fi signal',
                              value: _formatRssi(),
                            ),
                            const Divider(height: 1),
                            _InfoTile(
                              label: 'Firmware',
                              value: _device?.firmwareVersion ?? '--',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatusTile(ThemeData theme, ColorScheme colors) {
    final online = _device?.isOnline ?? false;
    return ListTile(
      title: const Text('Status'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(
            variant: online ? StatusDotVariant.online : StatusDotVariant.offline,
          ),
          const SizedBox(width: 6),
          Text(
            online ? 'Online' : 'Offline',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: online ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _formatUptime() {
    final device = _device;
    if (device == null || device.lastSeenAt == null) return '--';
    if (!device.isOnline) return 'Offline';
    final d = DateTime.now().difference(device.lastSeenAt!);
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }

  String _formatRssi() {
    final rssi = _device?.wifiRssi;
    if (rssi == null) return '--';
    final label = rssi >= -50
        ? 'Excellent'
        : rssi >= -60
            ? 'Good'
            : rssi >= -70
                ? 'Fair'
                : rssi >= -80
                    ? 'Weak'
                    : 'Poor';
    return '$label ($rssi dBm)';
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

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(label),
      trailing: Text(
        value,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
