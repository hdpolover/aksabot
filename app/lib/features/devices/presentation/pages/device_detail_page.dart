import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
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
                  : _DashboardBody(device: device),
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
// Dashboard body
// ---------------------------------------------------------------------------

class _DashboardBody extends StatelessWidget {
  final Device device;
  const _DashboardBody({required this.device});

  @override
  Widget build(BuildContext context) {
    final id = device.id;
    final cs = Theme.of(context).colorScheme;
    final ac = Theme.of(context).extension<AppColors>()!;

    return ListView(
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PrimaryCard(
                icon: Icons.timer_rounded,
                label: 'Pomodoro',
                description: 'Focus sessions',
                cardBg: ac.warningContainer,
                iconBg: ac.warning,
                iconFg: ac.onWarning,
                onTap: () => context.push('/devices/$id/pomodoro'),
              ),
            ),
            const SizedBox(width: AppConstants.spacingMd),
            Expanded(
              child: _PrimaryCard(
                icon: Icons.center_focus_strong_rounded,
                label: 'Focus',
                description: 'Deep work mode',
                cardBg: cs.primaryContainer,
                iconBg: cs.primary,
                iconFg: cs.onPrimary,
                onTap: () => context.push('/devices/$id/focus'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingMd),
        _WideCard(
          icon: Icons.notifications_active_rounded,
          label: 'Reminders',
          description: 'Health, hydration & daily routines',
          cardBg: ac.successContainer,
          iconBg: ac.success,
          iconFg: ac.onSuccess,
          onTap: () => context.push('/devices/$id/reminders'),
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
              icon: Icons.face_rounded,
              label: 'Personality',
              route: '/devices/$id/personality',
            ),
            _SettingsRowData(
              icon: Icons.monitor_rounded,
              label: 'Display & Face',
              route: '/devices/$id/display',
            ),
            _SettingsRowData(
              icon: Icons.bluetooth_searching_rounded,
              label: 'Presence Detection',
              route: '/devices/$id/presence',
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
              label: 'Stats & History',
              route: '/devices/$id/stats',
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Status card
// ---------------------------------------------------------------------------

class _StatusCard extends StatelessWidget {
  final Device device;
  const _StatusCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final online = device.isOnline;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingLg,
          vertical: AppConstants.spacingMd,
        ),
        child: Row(
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
              Text(
                '· ${device.wifiSsid}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            const Spacer(),
            if (device.lastSeenAt != null)
              Text(
                online
                    ? _formatUptime(
                        DateTime.now().difference(device.lastSeenAt!))
                    : _formatTimeAgo(device.lastSeenAt!),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.outline),
              ),
          ],
        ),
      ),
    );
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
// Primary cards (Pomodoro, Focus) — 2-col, prominent
// ---------------------------------------------------------------------------

class _PrimaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color cardBg;
  final Color iconBg;
  final Color iconFg;
  final VoidCallback onTap;

  const _PrimaryCard({
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
              const SizedBox(height: AppConstants.spacingMd),
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
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wide card (Reminders) — full-width, horizontal layout
// ---------------------------------------------------------------------------

class _WideCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color cardBg;
  final Color iconBg;
  final Color iconFg;
  final VoidCallback onTap;

  const _WideCard({
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
    final cs = theme.colorScheme;

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingLg,
            vertical: AppConstants.spacingMd,
          ),
          child: Row(
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
              const SizedBox(width: AppConstants.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.spacingMd),
              Icon(
                Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant,
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
// Settings group — grouped list rows in a card
// ---------------------------------------------------------------------------

class _SettingsRowData {
  final IconData icon;
  final String label;
  final String route;

  const _SettingsRowData({
    required this.icon,
    required this.label,
    required this.route,
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
        onTap: () => context.push(data.route),
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
