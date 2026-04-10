import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/local/local_device.dart';
import '../../../../core/local/local_device_store.dart';
import '../../../../core/local/mdns_discovery_service.dart';
import '../../../devices/domain/entities/device_entity.dart';
import '../../../devices/presentation/bloc/devices_bloc.dart';
import '../../../devices/presentation/pages/cloud_register_page.dart';

/// Home tab root. Shows a single-device dashboard when 1 device exists,
/// a device list when 2+, or an empty state when 0.
///
/// Falls back to locally-provisioned devices when the backend is unavailable.
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

class _HomeView extends StatefulWidget {
  const _HomeView();

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  List<LocalDevice>? _localDevices;

  @override
  void initState() {
    super.initState();
    _loadLocalDevices();
  }

  Future<void> _loadLocalDevices() async {
    final devices = await LocalDeviceStore.getAll();
    if (mounted) setState(() => _localDevices = devices);
  }

  void _pushAndReload(BuildContext context, String path) {
    final bloc = context.read<DevicesBloc>();
    context.push(path).then((_) {
      if (mounted) {
        bloc.add(const LoadDevices());
        _loadLocalDevices();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DevicesBloc, DevicesState>(
      builder: (context, state) {
        // While waiting for the bloc AND local devices, show spinner
        if (state is DevicesLoading && _localDevices == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Backend has devices — show them normally
        if (state is DevicesLoaded && state.devices.isNotEmpty) {
          if (state.devices.length == 1) {
            return _DeviceDashboard(
              device: state.devices.first,
              onNavigate: _pushAndReload,
            );
          }
          return _DeviceList(
            devices: state.devices,
            onNavigate: _pushAndReload,
          );
        }

        // Backend unavailable or empty — show local devices if any
        final locals = _localDevices ?? [];

        if (locals.isNotEmpty) {
          if (locals.length == 1) {
            return _LocalDeviceDashboard(
              device: locals.first,
              onAdd: () => _pushAndReload(context, '/devices/add'),
              onRemove: () async {
                await LocalDeviceStore.remove(locals.first.id);
                _loadLocalDevices();
              },
              onIpDiscovered: (ip) async {
                final updated = locals.first.copyWith(localIp: ip);
                await LocalDeviceStore.save(updated);
                _loadLocalDevices();
              },
              onRegistered: () {
                context.read<DevicesBloc>().add(const LoadDevices());
                _loadLocalDevices();
              },
            );
          }
          return _LocalDeviceList(
            devices: locals,
            onAdd: () => _pushAndReload(context, '/devices/add'),
            onRemove: (id) async {
              await LocalDeviceStore.remove(id);
              _loadLocalDevices();
            },
          );
        }

        // Truly empty — no backend, no local devices
        return _EmptyState(onNavigate: _pushAndReload);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final void Function(BuildContext, String) onNavigate;
  const _EmptyState({required this.onNavigate});

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
              Text('No devices yet', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Pair your Aksabot to get started',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => onNavigate(context, '/devices/add'),
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
// Local device dashboard (single, no backend)
// ---------------------------------------------------------------------------

enum _DiscoverState { idle, searching, found, notFound }

class _LocalDeviceDashboard extends StatefulWidget {
  final LocalDevice device;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final Future<void> Function(String ip) onIpDiscovered;
  final VoidCallback onRegistered;

  const _LocalDeviceDashboard({
    required this.device,
    required this.onAdd,
    required this.onRemove,
    required this.onIpDiscovered,
    required this.onRegistered,
  });

  @override
  State<_LocalDeviceDashboard> createState() => _LocalDeviceDashboardState();
}

class _LocalDeviceDashboardState extends State<_LocalDeviceDashboard> {
  _DiscoverState _discoverState = _DiscoverState.idle;

  Future<void> _discoverDevice() async {
    setState(() => _discoverState = _DiscoverState.searching);
    final found = await MdnsDiscoveryService().discoverFirst();
    if (!mounted) return;
    if (found != null) {
      setState(() => _discoverState = _DiscoverState.found);
      await widget.onIpDiscovered(found.ip);
    } else {
      setState(() => _discoverState = _DiscoverState.notFound);
    }
  }

  Future<void> _connectToBackend() async {
    final registered = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CloudRegisterPage(device: widget.device),
      ),
    );
    if (registered == true && mounted) {
      widget.onRegistered();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final device = widget.device;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + 16),

          // Header
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
                    Text(
                      device.name,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: device.localIp != null
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          device.localIp != null
                              ? 'Found on network'
                              : 'Wi-Fi connected — not synced',
                          style: theme.textTheme.bodySmall?.copyWith(
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
          const SizedBox(height: 16),

          // Info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Device Info',
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  _InfoRow(
                    icon: Icons.wifi,
                    label: 'Network',
                    value: device.ssid,
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.access_time,
                    label: 'Paired',
                    value: _formatDate(device.pairedAt),
                  ),
                  if (device.localIp != null) ...[
                    const SizedBox(height: 8),
                    _InfoRow(
                      icon: Icons.lan,
                      label: 'Local IP',
                      value: device.localIp!,
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      icon: Icons.public,
                      label: 'Address',
                      value: 'aksabot.local',
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Discover on network button (shown when IP not yet known)
          if (device.localIp == null) ...[
            _DiscoverButton(
              state: _discoverState,
              onTap: _discoverState == _DiscoverState.searching
                  ? null
                  : _discoverDevice,
            ),
            const SizedBox(height: 12),
          ],

          // Cloud sync / connect banner
          _CloudSyncBanner(
            onConnect: device.localIp != null ? _connectToBackend : null,
          ),
          const SizedBox(height: 20),

          // Danger zone
          OutlinedButton.icon(
            onPressed: () => _confirmRemove(context),
            icon: Icon(Icons.delete_outline, color: colors.error),
            label: Text('Remove Device',
                style: TextStyle(color: colors.error)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colors.error.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove device?'),
        content: Text(
            'This will remove "${widget.device.name}" from this app. '
            'The device will stay connected to Wi-Fi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onRemove();
  }
}

class _DiscoverButton extends StatelessWidget {
  final _DiscoverState state;
  final VoidCallback? onTap;

  const _DiscoverButton({required this.state, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    Widget icon;
    String label;
    Color? labelColor;

    switch (state) {
      case _DiscoverState.searching:
        icon = SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
        );
        label = 'Searching...';
        labelColor = colors.onSurfaceVariant;
        break;
      case _DiscoverState.found:
        icon = Icon(Icons.check_circle_outline, size: 20, color: Colors.green);
        label = 'Found on network!';
        labelColor = Colors.green;
        break;
      case _DiscoverState.notFound:
        icon = Icon(Icons.wifi_find, size: 20, color: colors.error);
        label = 'Not found — make sure device is on same network';
        labelColor = colors.error;
        break;
      case _DiscoverState.idle:
        icon = Icon(Icons.wifi_find, size: 20, color: colors.primary);
        label = 'Find device on network';
        labelColor = null;
        break;
    }

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: labelColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Local device list (multiple, no backend)
// ---------------------------------------------------------------------------

class _LocalDeviceList extends StatelessWidget {
  final List<LocalDevice> devices;
  final VoidCallback onAdd;
  final void Function(String id) onRemove;

  const _LocalDeviceList({
    required this.devices,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      floatingActionButton: FloatingActionButton(
        onPressed: onAdd,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _CloudSyncBanner(),
          const SizedBox(height: 12),
          ...devices.map((device) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.smart_toy_outlined,
                              color: colors.onPrimaryContainer),
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
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.orange,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    device.ssid,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: colors.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: colors.error),
                          onPressed: () => onRemove(device.id),
                        ),
                      ],
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Backend device list (backend online)
// ---------------------------------------------------------------------------

class _DeviceList extends StatelessWidget {
  final List<Device> devices;
  final void Function(BuildContext, String) onNavigate;
  const _DeviceList({required this.devices, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => onNavigate(context, '/devices/add'),
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
                onTap: () => onNavigate(context, '/devices/${device.id}'),
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
                                    color: online
                                        ? Colors.green
                                        : colors.outline,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  online ? 'Online' : 'Offline',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
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
// Backend device dashboard (single, backend online)
// ---------------------------------------------------------------------------

class _DeviceDashboard extends StatelessWidget {
  final Device device;
  final void Function(BuildContext, String) onNavigate;
  const _DeviceDashboard({required this.device, required this.onNavigate});

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
                                color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Status cards
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
                  for (final action in [
                    (Icons.face, 'Personality', 'personality'),
                    (Icons.notifications_active, 'Reminders', 'reminders'),
                    (Icons.timer, 'Pomodoro', 'pomodoro'),
                    (Icons.center_focus_strong, 'Focus Mode', 'focus'),
                    (Icons.bluetooth_searching, 'Presence', 'presence'),
                    (Icons.monitor, 'Display & Face', 'display'),
                    (Icons.graphic_eq, 'Voice & Audio', 'voice'),
                    (Icons.bar_chart, 'Stats', 'stats'),
                    (Icons.settings, 'Device Settings', 'settings'),
                  ]) ...[
                    _QuickActionTile(
                      icon: action.$1,
                      label: action.$2,
                      onTap: () =>
                          onNavigate(context, '/devices/${device.id}/${action.$3}'),
                    ),
                    if (action.$3 != 'settings') const Divider(height: 1),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Recent conversations
            Text('Recent Conversations', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading:
                    Icon(Icons.chat_bubble_outline, color: colors.primary, size: 20),
                title: Text(
                  'No recent conversations',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                subtitle: Text(
                  'Conversations will appear here once you start chatting.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _CloudSyncBanner extends StatelessWidget {
  /// If provided, shows a "Connect" action button.
  /// Pass null when the device IP is not yet known.
  final VoidCallback? onConnect;

  const _CloudSyncBanner({this.onConnect});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final hasAction = onConnect != null;

    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, hasAction ? 4 : 14, 10),
      decoration: BoxDecoration(
        color: hasAction
            ? colors.primaryContainer.withValues(alpha: 0.55)
            : colors.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            hasAction ? Icons.cloud_queue : Icons.cloud_off,
            size: 18,
            color: hasAction
                ? colors.onPrimaryContainer
                : colors.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasAction
                  ? 'Connect to AI cloud to unlock voice features.'
                  : 'Not synced — find device on network to connect to AI cloud.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: hasAction
                    ? colors.onPrimaryContainer
                    : colors.onSecondaryContainer,
              ),
            ),
          ),
          if (hasAction) ...[
            TextButton(
              onPressed: onConnect,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('Connect'),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 16, color: colors.onSurfaceVariant),
        const SizedBox(width: 8),
        Text('$label: ',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant)),
        Expanded(
          child: Text(value,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500)),
        ),
      ],
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
            Text(value,
                style: theme.textTheme.titleMedium?.copyWith(color: color)),
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
