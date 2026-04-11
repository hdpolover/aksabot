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
                  : DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          TabBar(
                            tabs: const [
                              Tab(text: 'Dashboard'),
                              Tab(text: 'Settings'),
                            ],
                            labelColor: colors.primary,
                            unselectedLabelColor: colors.onSurfaceVariant,
                            indicatorColor: colors.primary,
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _DashboardTab(device: device),
                                _SettingsTab(device: device),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
    const botName = 'Aksa';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // Hero header
        Center(
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: online
                        ? [colors.primary, colors.tertiary]
                        : [colors.surfaceContainerHighest, colors.surfaceContainerHigh],
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                ),
                child: Icon(
                  Icons.smart_toy_rounded,
                  size: 36,
                  color: online ? colors.onPrimary : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppConstants.spacingMd),
              Text(botName, style: theme.textTheme.headlineSmall),
              const SizedBox(height: AppConstants.spacingXs),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusDot(
                    variant: online
                        ? StatusDotVariant.online
                        : StatusDotVariant.offline,
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
        const SizedBox(height: AppConstants.spacingXxl),

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

// ---------------------------------------------------------------------------
// Settings tab
// ---------------------------------------------------------------------------

class _SettingsTab extends StatefulWidget {
  final Device device;
  const _SettingsTab({required this.device});

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  late final TextEditingController _nameController;
  bool _dirty = false;
  double _volume = 80;
  double _brightness = 80;
  bool _showTranscript = true;
  String _idleTimeout = '30';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.device.name);
    _nameController.addListener(_onChanged);
    // Load settings from device JSON
    final s = widget.device.settingsJson;
    _volume = (s['volume'] as num?)?.toDouble() ?? 80;
    _brightness = (s['brightness'] as num?)?.toDouble() ?? 80;
    _showTranscript = s['showTranscript'] as bool? ?? true;
    _idleTimeout = (s['idleTimeoutMinutes'] ?? 30).toString();
  }

  @override
  void didUpdateWidget(covariant _SettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id) {
      _nameController.text = widget.device.name;
      _dirty = false;
    }
  }

  void _onChanged() {
    final isDirty = _nameController.text.trim() != widget.device.name;
    if (isDirty != _dirty) setState(() => _dirty = isDirty);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    context.read<DevicesBloc>().add(
          UpdateSettings(widget.device.id, {
            'name': name,
            'volume': _volume.round(),
            'brightness': _brightness.round(),
            'showTranscript': _showTranscript,
            'idleTimeoutMinutes': int.parse(_idleTimeout),
          }),
        );
    setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final online = widget.device.isOnline;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // General section
        Text('General', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Device name
                Text('Device name', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  decoration:
                      const InputDecoration(hintText: 'Enter device name'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),

                // Volume
                Row(
                  children: [
                    Text('Volume', style: theme.textTheme.bodyMedium),
                    const Spacer(),
                    Text('${_volume.round()}%',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
                Slider(
                  value: _volume,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  onChanged: (v) => setState(() {
                    _volume = v;
                    _dirty = true;
                  }),
                ),

                // Brightness
                Row(
                  children: [
                    Text('Brightness', style: theme.textTheme.bodyMedium),
                    const Spacer(),
                    Text('${_brightness.round()}%',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
                Slider(
                  value: _brightness,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  onChanged: (v) => setState(() {
                    _brightness = v;
                    _dirty = true;
                  }),
                ),
                const SizedBox(height: 8),

                // Show transcript toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Show transcript', style: theme.textTheme.bodyMedium),
                    Switch(
                      value: _showTranscript,
                      onChanged: (v) => setState(() {
                        _showTranscript = v;
                        _dirty = true;
                      }),
                    ),
                  ],
                ),

                // Idle timeout
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Idle timeout', style: theme.textTheme.bodyMedium),
                    DropdownButton<String>(
                      value: _idleTimeout,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: '1', child: Text('1 min')),
                        DropdownMenuItem(value: '5', child: Text('5 min')),
                        DropdownMenuItem(value: '10', child: Text('10 min')),
                        DropdownMenuItem(value: '30', child: Text('30 min')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _idleTimeout = v;
                            _dirty = true;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Save button
        FilledButton(
          onPressed: _dirty ? _save : null,
          child: const Text('Save Settings'),
        ),
        const SizedBox(height: 24),

        // Device info
        Text('Device Info', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                title: const Text('Status'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusDot(
                      variant: online
                          ? StatusDotVariant.online
                          : StatusDotVariant.offline,
                    ),
                    const SizedBox(width: AppConstants.spacingSm),
                    Text(
                      online ? 'Online' : 'Offline',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Wi-Fi signal'),
                trailing: widget.device.wifiRssi != null
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _wifiIcon(widget.device.wifiRssi!),
                            size: 18,
                            color: _wifiColor(widget.device.wifiRssi!, colors),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _wifiLabel(widget.device.wifiRssi!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _wifiColor(widget.device.wifiRssi!, colors),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        widget.device.isOnline ? 'Connected' : 'N/A',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Uptime'),
                trailing: Text(
                  online && widget.device.lastSeenAt != null
                      ? _formatUptime(
                          DateTime.now().difference(widget.device.lastSeenAt!))
                      : 'Offline',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Firmware'),
                trailing: Text(
                  widget.device.firmwareVersion ?? 'N/A',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Remove device
        OutlinedButton.icon(
          onPressed: () => _confirmDelete(context),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Remove Device'),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.error,
            side: BorderSide(color: colors.error),
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      ],
    );
  }

  String _formatUptime(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }

  static String _wifiLabel(int rssi) {
    if (rssi > -50) return 'Excellent';
    if (rssi > -60) return 'Good';
    if (rssi > -70) return 'Fair';
    if (rssi > -80) return 'Weak';
    return 'Poor';
  }

  static IconData _wifiIcon(int rssi) {
    if (rssi > -60) return Icons.wifi;
    if (rssi > -70) return Icons.wifi_2_bar;
    return Icons.wifi_1_bar;
  }

  static Color _wifiColor(int rssi, ColorScheme colors) {
    if (rssi > -60) return colors.primary;
    if (rssi > -70) return colors.tertiary;
    return colors.error;
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Device'),
        content: Text('Remove "${widget.device.name}" permanently?'),
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
              bloc.add(DeleteDevice(widget.device.id));
              await bloc.stream.firstWhere(
                (s) => s is DevicesLoaded || s is DevicesError,
              );
              if (context.mounted) context.pop();
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

