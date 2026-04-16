import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../../../core/widgets/status_dot.dart';
import '../../data/models/device_stats_model.dart';
import '../../domain/entities/device_entity.dart';
import '../../domain/repositories/devices_repository.dart';
import '../bloc/devices_bloc.dart';
import 'ble_provisioning_page.dart';

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
    final colors = Theme.of(context).colorScheme;

    return BlocConsumer<DevicesBloc, DevicesState>(
      listener: (context, state) {
        if (state is DevicesError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        final device = state is DeviceDetailLoaded ? state.device : null;

        return Scaffold(
          appBar: AppBar(
            title: Text(device?.name ?? 'Device'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
                onPressed: () => context
                    .read<DevicesBloc>()
                    .add(LoadDevice(deviceId)),
              ),
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
                  : DeviceDashboardBody(device: device),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, Device device) async {
    final confirmed = await AppDialog.confirm(
      context,
      title: 'Delete Device',
      body: 'Remove "${device.name}" permanently?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;
    final bloc = context.read<DevicesBloc>();
    bloc.add(DeleteDevice(device.id));
    await bloc.stream.firstWhere((s) => s is DevicesLoaded || s is DevicesError);
    if (context.mounted) context.pop();
  }
}

// ---------------------------------------------------------------------------
// Dashboard body
// ---------------------------------------------------------------------------

class DeviceDashboardBody extends StatelessWidget {
  final Device device;
  const DeviceDashboardBody({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final id = device.id;
    final cs = Theme.of(context).colorScheme;
    final ac = Theme.of(context).extension<AppColors>()!;

    return RefreshIndicator(
      onRefresh: () async {
        context.read<DevicesBloc>().add(LoadDevice(device.id));
        await context.read<DevicesBloc>().stream.firstWhere(
              (s) => s is DeviceDetailLoaded || s is DevicesError,
            );
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingLg,
          AppConstants.spacingMd,
          AppConstants.spacingLg,
          AppConstants.spacingXxxl,
        ),
      children: [
        _StatusCard(device: device),
        const SizedBox(height: AppConstants.spacingXxl),

        // ── Right now ──────────────────────────────────────────────────────
        const _SectionLabel('Right now'),
        const SizedBox(height: AppConstants.spacingMd),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: AppConstants.spacingMd,
          mainAxisSpacing: AppConstants.spacingMd,
          childAspectRatio: 1.1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _GridCard(
              icon: Icons.notifications_active_rounded,
              label: 'Reminders',
              description: 'Health & daily routines',
              cardBg: ac.successContainer,
              iconBg: ac.success,
              iconFg: ac.onSuccess,
              onTap: () => context.push('/devices/$id/reminders'),
            ),
            _DisplayModeGridCard(device: device),
            _GridCard(
              icon: Icons.image_rounded,
              label: 'Push Image',
              description: 'Send a photo to the display',
              cardBg: cs.secondaryContainer,
              iconBg: cs.secondary,
              iconFg: cs.onSecondary,
              onTap: () => _showPushImageSheet(context, id),
            ),
            _GridCard(
              icon: Icons.surround_sound_rounded,
              label: 'Voice Intercom',
              description: 'Send a message or go live',
              cardBg: cs.tertiaryContainer,
              iconBg: cs.tertiary,
              iconFg: cs.onTertiary,
              onTap: () => context.push('/devices/$id/intercom'),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingXxl),

        // ── Bot ────────────────────────────────────────────────────────────
        const _SectionLabel('Bot'),
        const SizedBox(height: AppConstants.spacingMd),
        _SettingsGroup(
          items: [
            _SettingsRowData(
              icon: Icons.graphic_eq_rounded,
              label: 'Voice & Audio',
              route: '/devices/$id/voice',
            ),
            _SettingsRowData(
              icon: Icons.monitor_rounded,
              label: 'Display & Behavior',
              route: '/devices/$id/display',
            ),
            _SettingsRowData(
              icon: Icons.bluetooth_searching_rounded,
              label: 'Presence Detection',
              route: '/devices/$id/presence',
            ),
            _SettingsRowData(
              icon: Icons.timer_rounded,
              label: 'Pomodoro',
              route: '/devices/$id/pomodoro',
            ),
            _SettingsRowData(
              icon: Icons.center_focus_strong_rounded,
              label: 'Focus Mode',
              route: '/devices/$id/focus',
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingXxl),

        // ── Device ─────────────────────────────────────────────────────────
        const _SectionLabel('Device'),
        const SizedBox(height: AppConstants.spacingMd),
        _SettingsGroup(
          items: [
            _SettingsRowData(
              icon: Icons.extension_rounded,
              label: 'Integrations',
              route: '/devices/$id/integrations',
            ),
            _SettingsRowData(
              icon: Icons.settings_rounded,
              label: 'Settings',
              route: '/devices/$id/settings',
            ),
            _SettingsRowData(
              icon: Icons.bar_chart_rounded,
              label: 'Stats & Diagnostics',
              route: '/devices/$id/stats',
            ),
            _SettingsRowData(
              icon: Icons.system_update_rounded,
              label: 'Firmware Update',
              route: '/devices/$id/firmware',
              extra: device.firmwareVersion,
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingMd),
        _ReconnectRow(deviceId: id, deviceIsOnline: device.isOnline),
        const SizedBox(height: AppConstants.spacingMd),
        _PowerControlRow(deviceId: id, deviceIsOnline: device.isOnline),
      ],
    ),
    );
  }
}

Future<void> _setDisplayMode(BuildContext context, String deviceId, String mode) async {
  final repo = sl<DevicesRepository>();
  final result = await repo.updateSettings(deviceId, {'idle_display_mode': mode});
  if (!context.mounted) return;
  result.fold(
    (failure) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed: ${failure.message}')),
    ),
    (_) {
      final label = mode == 'clock' ? 'clock' : 'face';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Display switched to $label mode')),
      );
      context.read<DevicesBloc>().add(LoadDevice(deviceId));
    },
  );
}

void _showPushImageSheet(BuildContext context, String deviceId) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppConstants.radiusXl),
      ),
    ),
    builder: (_) => _PushImageSheet(deviceId: deviceId),
  );
}

// ---------------------------------------------------------------------------
// Push Image bottom sheet
// ---------------------------------------------------------------------------

class _PushImageSheet extends StatefulWidget {
  final String deviceId;
  const _PushImageSheet({required this.deviceId});

  @override
  State<_PushImageSheet> createState() => _PushImageSheetState();
}

class _PushImageSheetState extends State<_PushImageSheet> {
  final _picker = ImagePicker();

  Uint8List? _compressed;
  bool _picking = false;
  bool _sending = false;
  String? _error;
  int _durationSec = 10;

  // Screen size of the ESP32 display — compress to fit
  static const int _targetWidth = 240;
  static const int _targetHeight = 320;

  Future<void> _pick(ImageSource source) async {
    setState(() { _picking = true; _error = null; });
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 100);
      if (file == null) { setState(() => _picking = false); return; }

      final raw = await file.readAsBytes();

      // Resize to 240×320 at high quality — device has 2MB PSRAM budget for images
      final compressed = await FlutterImageCompress.compressWithList(
        raw,
        minWidth: _targetWidth,
        minHeight: _targetHeight,
        quality: 92,
        format: CompressFormat.jpeg,
      );

      setState(() { _compressed = compressed; _picking = false; });
    } catch (e) {
      setState(() { _error = 'Could not load image: $e'; _picking = false; });
    }
  }

  Future<void> _send() async {
    if (_compressed == null) return;
    setState(() { _sending = true; _error = null; });

    final repo = sl<DevicesRepository>();
    final result = await repo.pushImage(
      widget.deviceId,
      _compressed!,
      durationMs: _durationSec * 1000,
    );

    if (!mounted) return;
    result.fold(
      (failure) => setState(() { _sending = false; _error = failure.message; }),
      (_) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image sent to device')),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppConstants.spacingXxl,
        AppConstants.spacingLg,
        AppConstants.spacingXxl,
        AppConstants.spacingXxl + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingXxl),

          Text('Push Image to Device', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppConstants.spacingXs),
          Text(
            'Image is compressed to 240×320 JPEG before sending. '
            'Device downloads it over Wi-Fi and shows it on screen.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppConstants.spacingXxl),

          // Preview or picker buttons
          if (_compressed != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              child: Image.memory(
                _compressed!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: AppConstants.spacingXs),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${(_compressed!.length / 1024).toStringAsFixed(1)} KB',
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(width: AppConstants.spacingMd),
                TextButton(
                  onPressed: _picking || _sending ? null : () => setState(() => _compressed = null),
                  child: const Text('Change'),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _picking ? null : () => _pick(ImageSource.gallery),
                    icon: _picking
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.photo_library_rounded),
                    label: const Text('Gallery'),
                  ),
                ),
                const SizedBox(width: AppConstants.spacingMd),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _picking ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('Camera'),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: AppConstants.spacingXxl),

          // Duration slider
          Row(
            children: [
              Text('Show for:', style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(
                _durationSec == 0 ? 'Until dismissed' : '${_durationSec}s',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Slider(
            value: _durationSec.toDouble(),
            min: 0,
            max: 60,
            divisions: 12,
            onChanged: _sending ? null : (v) => setState(() => _durationSec = v.round()),
          ),

          if (_error != null) ...[
            const SizedBox(height: AppConstants.spacingSm),
            Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: cs.error)),
          ],

          const SizedBox(height: AppConstants.spacingMd),

          FilledButton(
            onPressed: _compressed == null || _sending ? null : _send,
            child: _sending
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Send to Device'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status card
// ---------------------------------------------------------------------------

class _StatusCard extends StatefulWidget {
  final Device device;
  const _StatusCard({required this.device});

  @override
  State<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends State<_StatusCard> {
  DeviceStats? _stats;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchStats();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _fetchStats(),
    );
  }

  @override
  void didUpdateWidget(_StatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id) {
      _fetchStats();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchStats() async {
    final repo = sl<DevicesRepository>();
    final result = await repo.getStats(widget.device.id);
    if (!mounted) return;
    result.fold(
      (_) {},
      (json) => setState(() => _stats = DeviceStats.fromJson(json)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ac = theme.extension<AppColors>()!;
    final online = device.isOnline;
    final s = device.settingsJson;

    final presenceEnabled = s['presence_enabled'] as bool? ?? false;
    final weatherEnabled = s['integrations_weather'] as bool? ?? false;
    final rssi = device.wifiRssi;

    // Build the feature pills that are active / relevant
    final pills = <_StatusPill>[
      if (online && presenceEnabled)
        _StatusPill(
          icon: Icons.sensors_rounded,
          label: 'Presence',
          color: ac.info,
        ),
      if (online && weatherEnabled)
        _StatusPill(
          icon: Icons.wb_sunny_rounded,
          label: 'Weather',
          color: cs.tertiary,
        ),
      if (online && rssi != null)
        _StatusPill(
          icon: _wifiIcon(rssi),
          label: _wifiLabel(rssi),
          color: _wifiColor(rssi, ac),
        ),
    ];

    return BlocListener<DevicesBloc, DevicesState>(
      listener: (context, state) {
        if (state is DeviceDetailLoaded && state.device.id == widget.device.id) {
          _fetchStats();
        }
      },
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingLg,
            vertical: AppConstants.spacingMd,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Connection row ───────────────────────────────────────
              Row(
              children: [
                StatusDot(
                  variant: online
                      ? StatusDotVariant.online
                      : StatusDotVariant.offline,
                ),
                const SizedBox(width: AppConstants.spacingSm),
                Text(
                  online ? 'Connected' : 'Offline',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: online ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (online && device.wifiSsid != null) ...[
                  const SizedBox(width: AppConstants.spacingXs),
                  Flexible(
                    child: Text(
                      '· ${device.wifiSsid}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const Spacer(),
                _buildBatteryIndicator(_stats, cs),
                if (device.lastSeenAt != null) ...[
                  if (_stats?.batteryPercent != null)
                    const SizedBox(width: AppConstants.spacingSm),
                  Text(
                    online
                        ? _formatUptime(
                            DateTime.now().difference(device.lastSeenAt!))
                        : _formatTimeAgo(device.lastSeenAt!),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.outline),
                  ),
                ],
              ],
            ),

            // ── Feature pills (only when there's something to show) ──
            if (pills.isNotEmpty) ...[
              const SizedBox(height: AppConstants.spacingMd),
              Wrap(
                spacing: AppConstants.spacingSm,
                runSpacing: AppConstants.spacingXs,
                children: pills.map((p) => _PillChip(pill: p)).toList(),
              ),
            ],

            // ── Offline hint ─────────────────────────────────────────
            if (!online && device.lastSeenAt == null) ...[
              const SizedBox(height: AppConstants.spacingXs),
              Text(
                'Never connected — make sure the device is powered on and provisioned.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildBatteryIndicator(DeviceStats? stats, ColorScheme cs) {
    if (stats == null) return const SizedBox.shrink();
    final pct = stats.batteryPercent;
    if (pct == null) return const SizedBox.shrink();

    // Use the explicit charging flag from firmware (trend + threshold based).
    // Fall back to pct == 255 for backwards compat with older firmware.
    final isCharging = stats.batteryCharging == true || pct == 255;

    if (isCharging) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.battery_charging_full, size: 14, color: Colors.green),
        const SizedBox(width: 4),
        Text('Charging',
            style: TextStyle(fontSize: 12, color: Colors.green)),
      ]);
    }
    final icon = pct > 60
        ? Icons.battery_full
        : pct > 30
            ? Icons.battery_3_bar
            : Icons.battery_alert;
    final color = pct <= 20 ? Colors.red : cs.onSurfaceVariant;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text('$pct%', style: TextStyle(fontSize: 12, color: color)),
    ]);
  }

  static String _formatUptime(Duration d) {
    if (d.inDays > 0) return 'Up ${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return 'Up ${d.inHours}h ${d.inMinutes % 60}m';
    return 'Up ${d.inMinutes}m';
  }

  static String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return '${diff.inMinutes}m ago';
  }

  static IconData _wifiIcon(int rssi) {
    if (rssi >= -60) return Icons.network_wifi_rounded;
    if (rssi >= -70) return Icons.network_wifi_2_bar_rounded;
    return Icons.network_wifi_1_bar_rounded;
  }

  static String _wifiLabel(int rssi) {
    if (rssi >= -60) return 'Excellent';
    if (rssi >= -70) return 'Good';
    if (rssi >= -80) return 'Fair';
    return 'Weak';
  }

  static Color _wifiColor(int rssi, AppColors ac) {
    if (rssi >= -60) return ac.success;
    if (rssi >= -70) return ac.info;
    if (rssi >= -80) return ac.warning;
    return ac.warning;
  }
}

class _StatusPill {
  final IconData icon;
  final String label;
  final Color color;
  const _StatusPill({required this.icon, required this.label, required this.color});
}

class _PillChip extends StatelessWidget {
  final _StatusPill pill;
  const _PillChip({required this.pill});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: pill.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(pill.icon, size: 13, color: pill.color),
          const SizedBox(width: 5),
          Text(
            pill.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: pill.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section label
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Wide card (Reminders) — full-width, horizontal layout
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Grid card — compact vertical layout for the 2×2 "Right now" grid
// ---------------------------------------------------------------------------

class _GridCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color cardBg;
  final Color iconBg;
  final Color iconFg;
  final VoidCallback onTap;

  const _GridCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.cardBg,
    required this.iconBg,
    required this.iconFg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Icon(icon, color: iconFg, size: AppConstants.iconMd),
              ),
              const Spacer(),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppConstants.spacingXxs),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
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
// Display mode toggle grid card
// ---------------------------------------------------------------------------

class _DisplayModeGridCard extends StatelessWidget {
  final Device device;
  const _DisplayModeGridCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentMode = device.settingsJson['idle_display_mode'] as String? ?? 'face';
    final isClockMode = currentMode == 'clock';

    return _GridCard(
      icon: isClockMode ? Icons.face_rounded : Icons.access_time_rounded,
      label: isClockMode ? 'Face Mode' : 'Clock Mode',
      description: isClockMode ? 'Switch back to animated face' : 'Switch to live clock',
      cardBg: cs.surfaceContainerHighest,
      iconBg: cs.onSurfaceVariant,
      iconFg: cs.surface,
      onTap: () => _setDisplayMode(
        context,
        device.id,
        isClockMode ? 'face' : 'clock',
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings group — grouped list rows in a card
// ---------------------------------------------------------------------------

class _SettingsRowData {
  final IconData icon;
  final String label;
  final String route;
  final Object? extra;

  const _SettingsRowData({
    required this.icon,
    required this.label,
    required this.route,
    this.extra,
  });
}

class _SettingsGroup extends StatelessWidget {
  final List<_SettingsRowData> items;
  const _SettingsGroup({required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _SettingsRowTile(data: items[i]),
            if (i < items.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                color: cs.outlineVariant.withValues(alpha: 0.5),
                indent: AppConstants.spacingLg +
                    AppConstants.spacingMd +
                    36, // align with text
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsRowTile extends StatelessWidget {
  final _SettingsRowData data;
  const _SettingsRowTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: cs.surfaceContainerHigh,
      child: InkWell(
        onTap: () => context.push(data.route, extra: data.extra),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingLg,
            vertical: AppConstants.spacingMd,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Icon(
                  data.icon,
                  color: cs.primary,
                  size: AppConstants.iconMd,
                ),
              ),
              const SizedBox(width: AppConstants.spacingMd),
              Expanded(
                child: Text(
                  data.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: cs.outlineVariant,
                size: AppConstants.iconLg,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Power control row — sleep + restart actions
// ---------------------------------------------------------------------------

class _PowerControlRow extends StatelessWidget {
  final String deviceId;
  final bool deviceIsOnline;
  const _PowerControlRow({
    required this.deviceId,
    required this.deviceIsOnline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: Material(
        color: cs.surfaceContainerHigh,
        child: Column(
          children: [
            _PowerAction(
              icon: Icons.bedtime_rounded,
              label: 'Sleep',
              subtitle: 'Turn off display and enter low-power mode',
              color: cs.tertiary,
              onTap: () async {
                final confirmed = await AppDialog.confirm(
                  context,
                  icon: Icons.bedtime_rounded,
                  title: 'Sleep Device?',
                  body: 'The display will turn off and the device will enter low-power mode. Wake it by tapping the screen.',
                  confirmLabel: 'Sleep',
                );
                if (confirmed == true && context.mounted) _sendCommand(context, 'sleep');
              },
            ),
            Divider(height: 1, indent: 56, color: cs.outlineVariant.withValues(alpha: 0.5)),
            _PowerAction(
              icon: Icons.restart_alt_rounded,
              label: 'Restart',
              subtitle: 'Soft reboot — reconnects in ~15 seconds',
              color: cs.error,
              onTap: () async {
                final confirmed = await AppDialog.confirm(
                  context,
                  icon: Icons.restart_alt_rounded,
                  title: 'Restart Device?',
                  body: 'The device will reboot and reconnect in about 15 seconds.',
                  confirmLabel: 'Restart',
                );
                if (confirmed == true && context.mounted) _sendCommand(context, 'restart');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendCommand(BuildContext context, String command) async {
    final repo = sl<DevicesRepository>();
    final result = command == 'sleep'
        ? await repo.sleepDevice(deviceId)
        : await repo.restartDevice(deviceId);
    if (!context.mounted) return;
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${failure.message}')),
      ),
      (_) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(command == 'sleep' ? 'Sleep command sent' : 'Restart command sent')),
      ),
    );
  }

}

class _PowerAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _PowerAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingLg,
          vertical: AppConstants.spacingMd,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              ),
              child: Icon(icon, color: color, size: AppConstants.iconMd),
            ),
            const SizedBox(width: AppConstants.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: cs.outlineVariant,
              size: AppConstants.iconLg,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Re-provision row — standalone card below Device settings group
// ---------------------------------------------------------------------------

class _ReconnectRow extends StatelessWidget {
  final String deviceId;
  final bool deviceIsOnline;
  const _ReconnectRow({
    required this.deviceId,
    required this.deviceIsOnline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      child: Material(
        color: cs.surfaceContainerHigh,
        child: InkWell(
          onTap: () => _showReconnectSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingLg,
              vertical: AppConstants.spacingMd,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  ),
                  child: Icon(
                    Icons.sync_rounded,
                    color: cs.secondary,
                    size: AppConstants.iconMd,
                  ),
                ),
                const SizedBox(width: AppConstants.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Re-provision / Change Wi-Fi',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'Update Wi-Fi credentials without losing data',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: cs.outlineVariant,
                  size: AppConstants.iconLg,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showReconnectSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXl),
        ),
      ),
      builder: (_) => _ReconnectSheet(
        deviceId: deviceId,
        deviceIsOnline: deviceIsOnline,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reconnect bottom sheet
// ---------------------------------------------------------------------------

class _ReconnectSheet extends StatefulWidget {
  final String deviceId;
  final bool deviceIsOnline;
  const _ReconnectSheet({
    required this.deviceId,
    required this.deviceIsOnline,
  });

  @override
  State<_ReconnectSheet> createState() => _ReconnectSheetState();
}

class _ReconnectSheetState extends State<_ReconnectSheet> {
  _SheetStep _step = _SheetStep.choose;
  String? _error;

  // Countdown (wait-for-reboot step)
  static const _countdownStart = 6;
  int _countdown = _countdownStart;
  Timer? _countdownTimer;
  Timer? _offlinePoller;

  // Online poller (wait-for-online step)
  Timer? _onlinePoller;
  bool _deviceBackOnline = false;
  int _waitingSeconds = 0;
  static const _onlineTimeoutSeconds = 90;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _offlinePoller?.cancel();
    _onlinePoller?.cancel();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingXxl,
          AppConstants.spacingLg,
          AppConstants.spacingXxl,
          AppConstants.spacingXxl,
        ),
        child: AnimatedSwitcher(
          duration: AppConstants.animFast,
          child: switch (_step) {
            _SheetStep.choose => _buildChooseStep(),
            _SheetStep.signaling => _buildSignalingStep(),
            _SheetStep.countdown => _buildCountdownStep(),
            _SheetStep.offlineInstructions => _buildOfflineStep(),
            _SheetStep.waitingOnline => _buildWaitingOnlineStep(),
          },
        ),
      ),
    );
  }

  // ── Step: choose ───────────────────────────────────────

  Widget _buildChooseStep() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      key: const ValueKey('choose'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetHandle(cs: cs),
        const SizedBox(height: AppConstants.spacingXxl),
        Text('Re-provision Device', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppConstants.spacingSm),
        Text(
          'Use this when you\'ve changed your Wi-Fi network or password. '
          'Your conversations, memories, and settings are kept.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppConstants.spacingXxl),

        if (widget.deviceIsOnline) ...[
          FilledButton.icon(
            onPressed: _signalDevice,
            icon: const Icon(Icons.wifi_tethering_rounded),
            label: const Text('Signal device to enter setup mode'),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Center(
            child: TextButton(
              onPressed: () =>
                  setState(() => _step = _SheetStep.offlineInstructions),
              child: const Text('Device not responding? Do it manually'),
            ),
          ),
        ] else ...[
          OutlinedButton.icon(
            onPressed: () =>
                setState(() => _step = _SheetStep.offlineInstructions),
            icon: const Icon(Icons.power_settings_new_rounded),
            label: const Text('Put device in setup mode manually'),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            'Device is offline — hold BOOT while powering on.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],

        if (_error != null) ...[
          const SizedBox(height: AppConstants.spacingMd),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  // ── Step: signaling ────────────────────────────────────

  Widget _buildSignalingStep() {
    final theme = Theme.of(context);

    return Column(
      key: const ValueKey('signaling'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: AppConstants.spacingXxl),
        SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: AppConstants.spacingXxl),
        Text(
          'Signaling device…',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: AppConstants.spacingSm),
        Text(
          'Sending the reboot command.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppConstants.spacingXxl),
      ],
    );
  }

  // ── Step: countdown ────────────────────────────────────

  Widget _buildCountdownStep() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ac = theme.extension<AppColors>()!;
    final ready = _countdown <= 0;

    return Column(
      key: const ValueKey('countdown'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  value: ready ? 1.0 : (_countdownStart - _countdown) / _countdownStart,
                  color: ready ? ac.success : cs.primary,
                  backgroundColor: cs.surfaceContainerHigh,
                ),
              ),
              if (ready)
                Icon(Icons.check_rounded, color: ac.success, size: 36)
              else
                Text(
                  '$_countdown',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacingXxl),
        Text(
          ready ? 'Device is rebooting' : 'Command sent',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: AppConstants.spacingSm),
        Text(
          ready
              ? 'Keep your phone close — starting BLE setup.'
              : 'Waiting for device to reboot… keep your phone close.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppConstants.spacingXxl),
        FilledButton(
          onPressed: ready ? _startBleProvisioning : null,
          child: const Text('Continue to BLE setup'),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  // ── Step: offline instructions ─────────────────────────

  Widget _buildOfflineStep() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      key: const ValueKey('offline'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetHandle(cs: cs),
        const SizedBox(height: AppConstants.spacingXxl),
        Text('Put device in setup mode', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppConstants.spacingMd),
        for (final (i, text) in [
          'Power off your Aksabot',
          'Hold the BOOT button (small button on the board)',
          'Power it back on — keep holding BOOT until the splash screen appears',
          'Release BOOT — device will enter BLE setup mode',
          'Come back here and tap Continue',
        ].indexed) ...[
          _InstructionRow(number: '${i + 1}', text: text),
          if (i < 4) const SizedBox(height: AppConstants.spacingMd),
        ],
        const SizedBox(height: AppConstants.spacingXxl),
        FilledButton(
          onPressed: _startBleProvisioning,
          child: const Text('Continue to BLE setup'),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        TextButton(
          onPressed: () => setState(() => _step = _SheetStep.choose),
          child: const Text('Back'),
        ),
      ],
    );
  }

  // ── Step: waiting for device to come back online ───────

  Widget _buildWaitingOnlineStep() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ac = theme.extension<AppColors>()!;
    final timedOut = _waitingSeconds >= _onlineTimeoutSeconds;

    return Column(
      key: const ValueKey('waitingOnline'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _deviceBackOnline
                  ? ac.successContainer
                  : cs.primaryContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: _deviceBackOnline
                ? Icon(Icons.check_rounded, color: ac.success, size: 40)
                : timedOut
                    ? Icon(Icons.schedule_rounded,
                        color: cs.onSurfaceVariant, size: 36)
                    : Padding(
                        padding: const EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: cs.primary,
                        ),
                      ),
          ),
        ),
        const SizedBox(height: AppConstants.spacingXxl),
        Text(
          _deviceBackOnline
              ? 'Device is back online!'
              : timedOut
                  ? 'Taking longer than expected'
                  : 'Waiting for device to reconnect…',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: AppConstants.spacingSm),
        Text(
          _deviceBackOnline
              ? 'Everything is set up. Your device reconnected successfully.'
              : timedOut
                  ? 'The device should come online in a moment. '
                      'Pull to refresh on the home screen to check.'
                  : 'The device is connecting to Wi-Fi with the new credentials.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppConstants.spacingXxl),
        FilledButton(
          onPressed: _closeAndRefresh,
          child: Text(_deviceBackOnline ? 'Done' : 'Close'),
        ),
      ],
    );
  }

  // ── Actions ────────────────────────────────────────────

  Future<void> _signalDevice() async {
    setState(() {
      _error = null;
      _step = _SheetStep.signaling;
    });

    final repo = sl<DevicesRepository>();
    final result = await repo.requestProvision(widget.deviceId);

    if (!mounted) return;

    result.fold(
      (failure) {
        setState(() {
          _step = _SheetStep.choose;
          _error = 'Failed to signal device: ${failure.message}';
        });
      },
      (_) => _startCountdown(),
    );
  }

  void _startCountdown() {
    setState(() {
      _countdown = _countdownStart;
      _step = _SheetStep.countdown;
    });

    // Tick down every second
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown = (_countdown - 1).clamp(0, _countdownStart));
      if (_countdown <= 0) t.cancel();
    });

    // Poll for device going offline — once it does, auto-advance
    _offlinePoller = Timer.periodic(const Duration(seconds: 2), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      final repo = sl<DevicesRepository>();
      final result = await repo.getDevice(widget.deviceId);
      result.fold((_) {}, (device) {
        if (!device.isOnline && mounted && _step == _SheetStep.countdown) {
          t.cancel();
          _countdownTimer?.cancel();
          setState(() => _countdown = 0); // unlock button
        }
      });
    });
  }

  Future<void> _startBleProvisioning() async {
    _countdownTimer?.cancel();
    _offlinePoller?.cancel();

    // Push BLE provisioning in changeWifiMode — skips re-registration,
    // only re-writes Wi-Fi credentials to this existing device.
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => const BleProvisioningPage(changeWifiMode: true),
      ),
    );

    if (!mounted) return;

    // BLE page was popped — start polling for device to come back online
    _startOnlinePolling();
  }

  void _startOnlinePolling() {
    setState(() {
      _step = _SheetStep.waitingOnline;
      _waitingSeconds = 0;
      _deviceBackOnline = false;
    });

    _onlinePoller = Timer.periodic(const Duration(seconds: 3), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      _waitingSeconds += 3;

      if (_waitingSeconds >= _onlineTimeoutSeconds) {
        t.cancel();
        setState(() {}); // show timeout UI
        return;
      }

      final repo = sl<DevicesRepository>();
      final result = await repo.getDevice(widget.deviceId);
      result.fold((_) {}, (device) {
        if (device.isOnline && mounted) {
          t.cancel();
          setState(() => _deviceBackOnline = true);
        }
      });
    });
  }

  void _closeAndRefresh() {
    _onlinePoller?.cancel();
    Navigator.of(context).pop();
    // Trigger a device list refresh so the home page status card updates
    context.read<DevicesBloc>().add(const LoadDevices());
  }
}

enum _SheetStep { choose, signaling, countdown, offlineInstructions, waitingOnline }

// ---------------------------------------------------------------------------
// Sheet handle — reusable drag handle bar for bottom sheets
// ---------------------------------------------------------------------------

class _SheetHandle extends StatelessWidget {
  final ColorScheme cs;
  const _SheetHandle({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: cs.outlineVariant,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Instruction row (shared with offline step)
// ---------------------------------------------------------------------------

class _InstructionRow extends StatelessWidget {
  final String number;
  final String text;
  const _InstructionRow({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppConstants.spacingMd),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(text, style: theme.textTheme.bodyMedium),
          ),
        ),
      ],
    );
  }
}
