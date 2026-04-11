import 'package:flutter/material.dart';

import '../../domain/repositories/devices_repository.dart';
import '../../../scheduler/domain/repositories/scheduler_repository.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';

/// Device statistics screen — wired to GET /devices/:id/stats and pool endpoints.
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

  // Stats from backend
  int _conversationsToday = 0;
  int _totalConversations = 0;
  int _totalMemories = 0;
  int _poolSize = 0;

  // Pool stats (separate endpoint)
  int _poolTotal = 0;
  int _poolUsed = 0;

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

    final statsResult = await _devicesRepo.getStats(widget.deviceId);
    statsResult.fold(
      (failure) => setState(() {
        _error = failure.message;
        _isLoading = false;
      }),
      (stats) {
        setState(() {
          _conversationsToday = stats['conversationsToday'] as int? ?? 0;
          _totalConversations = stats['totalConversations'] as int? ?? 0;
          _totalMemories = stats['totalMemories'] as int? ?? 0;
          _poolSize = stats['poolSize'] as int? ?? 0;
          _isLoading = false;
        });
      },
    );

    // Also load pool stats (best effort)
    final poolResult = await _schedulerRepo.getPoolStats(widget.deviceId);
    poolResult.fold(
      (_) => null,
      (data) => setState(() {
        _poolTotal = data['total'] as int? ?? _poolSize;
        _poolUsed = data['used'] as int? ?? 0;
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
        _loadAll(); // Refresh stats
      },
    );
    if (mounted) setState(() => _isRefilling = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
      body: _isLoading
          ? const AppLoadingIndicator()
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!,
                          style: TextStyle(color: colors.error)),
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
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Today's stats
                      Text('Today', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              value: '$_conversationsToday',
                              label: 'Conversations',
                              icon: Icons.chat_bubble_outline,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              value: '$_totalMemories',
                              label: 'Memories',
                              icon: Icons.psychology,
                              color: colors.tertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              value: '$_totalConversations',
                              label: 'Total convos',
                              icon: Icons.history,
                              color: colors.secondary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              value: '$_poolSize',
                              label: 'Pool entries',
                              icon: Icons.inventory_2_outlined,
                              color: colors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Cache info
                      Text('Response Pool', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            ListTile(
                              title: const Text('Pool entries'),
                              trailing: Text(
                                '$_poolUsed / $_poolTotal',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const Divider(height: 1),
                            ListTile(
                              title: const Text('Refill pool'),
                              trailing: FilledButton.tonal(
                                onPressed: _isRefilling ? null : _refillPool,
                                child: Text(
                                    _isRefilling ? 'Refilling...' : 'Refill'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // System info (from BLE — placeholder for now)
                      Text('System', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            _InfoTile(label: 'Uptime', value: '--'),
                            const Divider(height: 1),
                            _InfoTile(label: 'Free PSRAM', value: '--'),
                            const Divider(height: 1),
                            _InfoTile(label: 'Wi-Fi RSSI', value: '--'),
                            const Divider(height: 1),
                            _InfoTile(label: 'Flash used', value: '--'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'System stats require BLE connection to device.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

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
