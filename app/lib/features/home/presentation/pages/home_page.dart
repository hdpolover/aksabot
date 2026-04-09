import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../devices/domain/entities/device_entity.dart';
import '../../../devices/presentation/bloc/devices_bloc.dart';

/// Home tab root. Shows a single-device dashboard when 1 device exists,
/// a device list when 2+, or an empty state when 0.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<DevicesBloc>()..add(const LoadDevices()),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DevicesBloc, DevicesState>(
      builder: (context, state) {
        if (state is DevicesLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state is DevicesError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      size: 48, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 16),
                  Text(state.message),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: () =>
                        context.read<DevicesBloc>().add(const LoadDevices()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        if (state is DevicesLoaded) {
          if (state.devices.isEmpty) {
            return const _EmptyState();
          }
          if (state.devices.length == 1) {
            return _DeviceDashboard(device: state.devices.first);
          }
          return _DeviceList(devices: state.devices);
        }

        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state — no devices
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.smart_toy_rounded, size: 80, color: colors.primary),
              const SizedBox(height: 24),
              Text(
                'No devices yet',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Pair your Aksabot to get started',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => context.push('/home/add-device'),
                icon: const Icon(Icons.add),
                label: const Text('Add Device'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Multi-device list
// ---------------------------------------------------------------------------

class _DeviceList extends StatelessWidget {
  final List<Device> devices;
  const _DeviceList({required this.devices});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/home/add-device'),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          context.read<DevicesBloc>().add(const LoadDevices());
        },
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: devices.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final device = devices[index];
            final online = device.isOnline;

            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () =>
                    context.push('/home/devices/${device.id}'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: online
                              ? colors.primaryContainer
                              : colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.smart_toy_outlined,
                          color: online
                              ? colors.onPrimaryContainer
                              : colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(device.name,
                                style: theme.textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color:
                                        online ? Colors.green : colors.outline,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  online ? 'Online' : 'Offline',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: colors.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Single-device dashboard
// ---------------------------------------------------------------------------

class _DeviceDashboard extends StatelessWidget {
  final Device device;
  const _DeviceDashboard({required this.device});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final online = device.isOnline;
    final botName =
        (device.personalityJson['name'] as String?)?.isNotEmpty == true
            ? device.personalityJson['name'] as String
            : device.name;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          context.read<DevicesBloc>().add(const LoadDevices());
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            // Safe area top padding
            SizedBox(height: MediaQuery.of(context).padding.top + 16),

            // Status header
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.smart_toy_rounded,
                      size: 32, color: colors.onPrimaryContainer),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(botName,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: online ? Colors.green : colors.outline,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            online ? 'Online' : 'Offline',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Status cards row
            Row(
              children: [
                Expanded(
                  child: _StatusCard(
                    icon: Icons.center_focus_strong,
                    label: 'Focus Mode',
                    value: 'OFF',
                    color: colors.outline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatusCard(
                    icon: Icons.timer,
                    label: 'Pomodoro',
                    value: 'Idle',
                    color: colors.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Quick actions
            Text('Quick Actions', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _QuickActionTile(
                    icon: Icons.face,
                    label: 'Personality',
                    onTap: () => context
                        .push('/home/devices/${device.id}/personality'),
                  ),
                  const Divider(height: 1),
                  _QuickActionTile(
                    icon: Icons.notifications_active,
                    label: 'Reminders',
                    onTap: () => context
                        .push('/home/devices/${device.id}/reminders'),
                  ),
                  const Divider(height: 1),
                  _QuickActionTile(
                    icon: Icons.timer,
                    label: 'Pomodoro',
                    onTap: () => context
                        .push('/home/devices/${device.id}/pomodoro'),
                  ),
                  const Divider(height: 1),
                  _QuickActionTile(
                    icon: Icons.center_focus_strong,
                    label: 'Focus Mode',
                    onTap: () =>
                        context.push('/home/devices/${device.id}/focus'),
                  ),
                  const Divider(height: 1),
                  _QuickActionTile(
                    icon: Icons.bluetooth_searching,
                    label: 'Presence',
                    onTap: () => context
                        .push('/home/devices/${device.id}/presence'),
                  ),
                  const Divider(height: 1),
                  _QuickActionTile(
                    icon: Icons.monitor,
                    label: 'Display & Face',
                    onTap: () => context
                        .push('/home/devices/${device.id}/display'),
                  ),
                  const Divider(height: 1),
                  _QuickActionTile(
                    icon: Icons.graphic_eq,
                    label: 'Voice & Audio',
                    onTap: () =>
                        context.push('/home/devices/${device.id}/voice'),
                  ),
                  const Divider(height: 1),
                  _QuickActionTile(
                    icon: Icons.bar_chart,
                    label: 'Stats',
                    onTap: () =>
                        context.push('/home/devices/${device.id}/stats'),
                  ),
                  const Divider(height: 1),
                  _QuickActionTile(
                    icon: Icons.settings,
                    label: 'Device Settings',
                    onTap: () => context
                        .push('/home/devices/${device.id}/settings'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Recent conversations
            Text('Recent Conversations', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.chat_bubble_outline,
                        color: colors.primary, size: 20),
                    title: Text(
                      'No recent conversations',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    subtitle: Text(
                      'Conversations will appear here once you start chatting.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatusCard({
    required this.icon,
    required this.label,
    required this.value,
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
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 2),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
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
    final colors = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(icon, color: colors.primary),
      title: Text(label),
      trailing: Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
      onTap: onTap,
    );
  }
}
