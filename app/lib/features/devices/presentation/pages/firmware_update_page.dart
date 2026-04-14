import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../../firmware/presentation/bloc/firmware_bloc.dart';
import '../../../firmware/presentation/bloc/firmware_event.dart';
import '../../../firmware/presentation/bloc/firmware_state.dart';
import '../../../firmware/domain/entities/firmware_release.dart';
import '../../../firmware/domain/entities/ota_status.dart';

class FirmwareUpdatePage extends StatelessWidget {
  final String deviceId;
  final String? currentVersion;

  const FirmwareUpdatePage({
    super.key,
    required this.deviceId,
    this.currentVersion,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<FirmwareBloc>()..add(FirmwarePageOpened(deviceId)),
      child: _FirmwareView(
        deviceId: deviceId,
        currentVersion: currentVersion,
      ),
    );
  }
}

class _FirmwareView extends StatelessWidget {
  final String deviceId;
  final String? currentVersion;

  const _FirmwareView({required this.deviceId, this.currentVersion});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Firmware Update')),
      body: BlocBuilder<FirmwareBloc, FirmwareState>(
        builder: (context, state) {
          if (state is FirmwareLoading || state is FirmwareInitial) {
            return const AppLoadingIndicator();
          }
          if (state is FirmwareError) {
            return _ErrorBody(message: state.message);
          }
          if (state is FirmwareTriggerInProgress) {
            return const AppLoadingIndicator();
          }
          if (state is FirmwareLoaded) {
            return _LoadedBody(
              deviceId: deviceId,
              currentVersion: currentVersion,
              latest: state.latest,
              otaStatus: state.otaStatus,
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ── Loaded body ──────────────────────────────────────────────────

class _LoadedBody extends StatelessWidget {
  final String deviceId;
  final String? currentVersion;
  final FirmwareRelease? latest;
  final OtaStatus otaStatus;

  const _LoadedBody({
    required this.deviceId,
    required this.currentVersion,
    required this.latest,
    required this.otaStatus,
  });

  bool get _hasUpdate =>
      latest != null &&
      (currentVersion == null || currentVersion != latest!.version);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Version cards ───────────────────────────────────────────
        Text('Version', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.memory),
                title: const Text('Installed'),
                trailing: Text(
                  currentVersion ?? 'Unknown',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              if (latest != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.system_update,
                    color: _hasUpdate ? colors.primary : colors.onSurfaceVariant,
                  ),
                  title: const Text('Available'),
                  trailing: Text(
                    latest!.version,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _hasUpdate ? colors.primary : colors.onSurfaceVariant,
                      fontWeight: _hasUpdate ? FontWeight.bold : null,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: const Text('Size'),
                  trailing: Text(
                    _formatBytes(latest!.size),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Changelog ──────────────────────────────────────────────
        if (latest != null && latest!.changelog != null) ...[
          Text("What's new in ${latest!.version}",
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(latest!.changelog!),
            ),
          ),
          const SizedBox(height: 24),
        ],

        // ── OTA progress / action ───────────────────────────────────
        if (otaStatus.isActive || otaStatus.state == OtaState.complete ||
            otaStatus.state == OtaState.error)
          _OtaProgressCard(otaStatus: otaStatus)
        else if (latest == null)
          _NoReleasesCard()
        else if (!_hasUpdate)
          _UpToDateCard()
        else
          _UpdateButton(
            deviceId: deviceId,
            releaseId: latest!.id,
          ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────

class _OtaProgressCard extends StatelessWidget {
  final OtaStatus otaStatus;
  const _OtaProgressCard({required this.otaStatus});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (otaStatus.state == OtaState.complete) {
      return Card(
        color: colors.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: colors.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Update complete',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    if (otaStatus.version != null)
                      Text(
                        'Aksa is rebooting into ${otaStatus.version}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onPrimaryContainer,
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

    if (otaStatus.state == OtaState.error) {
      return Card(
        color: colors.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: colors.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Update failed',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.onErrorContainer,
                      ),
                    ),
                    if (otaStatus.error != null)
                      Text(
                        otaStatus.error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onErrorContainer,
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

    // Active: triggered or in_progress
    final phase = otaStatus.phase;
    final label = switch (phase) {
      'flashing' => 'Installing…',
      'verified' => 'Preparing to flash…',
      _ => 'Downloading…',
    };
    final progress = otaStatus.progress / 100.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleSmall),
                Text('${otaStatus.progress}%'),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: phase == 'flashing' ? null : progress,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.warning_amber,
                    size: 16,
                    color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Do not power off Aksa during the update.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateButton extends StatelessWidget {
  final String deviceId;
  final String releaseId;
  const _UpdateButton({required this.deviceId, required this.releaseId});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => context.read<FirmwareBloc>().add(
            FirmwareOtaTriggered(deviceId, releaseId: releaseId),
          ),
      icon: const Icon(Icons.system_update),
      label: const Text('Update Now'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
      ),
    );
  }
}

class _UpToDateCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: colors.onPrimaryContainer),
            const SizedBox(width: 12),
            Text(
              'Firmware is up to date',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoReleasesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No firmware available',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              'Upload a compiled .bin to the backend first:\n'
              'curl -X POST \$BACKEND_URL/firmware \\\n'
              '  -H "Authorization: Bearer <token>" \\\n'
              '  -F "file=@firmware.bin" \\\n'
              '  -F "version=1.0.0"',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  const _ErrorBody({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}
