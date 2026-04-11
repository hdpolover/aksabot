import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../../../core/widgets/status_dot.dart';
import '../../domain/entities/device_entity.dart';
import '../bloc/devices_bloc.dart';

class DeviceDetailPage extends StatelessWidget {
  final String deviceId;
  const DeviceDetailPage({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<DevicesBloc>()..add(LoadDevice(deviceId)),
      child: _DeviceDetailView(deviceId: deviceId),
    );
  }
}

class _DeviceDetailView extends StatelessWidget {
  final String deviceId;
  const _DeviceDetailView({required this.deviceId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return BlocConsumer<DevicesBloc, DevicesState>(
      listener: (context, state) {
        if (state is DevicesError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        final device =
            state is DeviceDetailLoaded ? state.device : null;

        return Scaffold(
          appBar: AppBar(
            title: Text(device?.name ?? 'Device'),
            actions: [
              if (device != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete device',
                  onPressed: () => _confirmDelete(context, device),
                ),
            ],
          ),
          body: state is DevicesLoading
              ? const AppLoadingIndicator()
              : device == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline,
                              size: 48, color: colors.error),
                          const SizedBox(height: 16),
                          FilledButton.tonal(
                            onPressed: () => context
                                .read<DevicesBloc>()
                                .add(LoadDevice(deviceId)),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _DashboardTab(device: device),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, Device device) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Device'),
        content: Text('Remove "${device.name}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final bloc = context.read<DevicesBloc>();
              bloc.add(DeleteDevice(device.id));
              // Wait for the bloc to finish the delete before popping
              await bloc.stream.firstWhere(
                (s) => s is DevicesLoaded || s is DevicesError,
              );
              if (context.mounted) context.pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard tab
// ---------------------------------------------------------------------------

class _DashboardTab extends StatelessWidget {
  final Device device;
  const _DashboardTab({required this.device});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final online = device.isOnline;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Compact status bar
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            child: Row(
              children: [
                StatusDot(
                  variant: online
                      ? StatusDotVariant.online
                      : StatusDotVariant.offline,
                ),
                const SizedBox(width: 8),
                Text(
                  online ? 'Connected' : 'Offline',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: online ? colors.primary : colors.onSurfaceVariant,
                  ),
                ),
                if (online && device.wifiSsid != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    device.wifiSsid!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                const Spacer(),
                if (device.lastSeenAt != null)
                  Text(
                    online
                        ? 'Up ${_formatUptime(DateTime.now().difference(device.lastSeenAt!))}'
                        : 'Last seen ${_formatTimeAgo(device.lastSeenAt!)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.outline,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spacingLg),

        // Quick actions
        Text('Quick Actions', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppConstants.spacingMd),
        GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: AppConstants.spacingSm,
          crossAxisSpacing: AppConstants.spacingSm,
          childAspectRatio: 1.0,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final action in [
              (Icons.face, 'Personality', 'personality'),
              (Icons.notifications_active, 'Reminders', 'reminders'),
              (Icons.timer, 'Pomodoro', 'pomodoro'),
              (Icons.center_focus_strong, 'Focus', 'focus'),
              (Icons.bluetooth_searching, 'Presence', 'presence'),
              (Icons.monitor, 'Display', 'display'),
              (Icons.graphic_eq, 'Audio', 'voice'),
              (Icons.bar_chart, 'Stats', 'stats'),
              (Icons.extension, 'Integrations', 'integrations'),
              (Icons.settings, 'Settings', 'settings'),
            ])
              _QuickActionTile(
                icon: action.$1,
                label: action.$2,
                onTap: () =>
                    context.push('/devices/${device.id}/${action.$3}'),
              ),
          ],
        ),
      ],
    );
  }

  static String _formatUptime(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }

  static String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return '${diff.inMinutes}m ago';
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Icon(icon, color: colors.primary, size: AppConstants.iconMd),
              ),
              const SizedBox(height: AppConstants.spacingSm),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


