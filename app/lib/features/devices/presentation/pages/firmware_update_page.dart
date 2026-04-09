import 'package:flutter/material.dart';

/// OTA Firmware Update screen — planned UI.
class FirmwareUpdatePage extends StatefulWidget {
  final String deviceId;
  const FirmwareUpdatePage({super.key, required this.deviceId});

  @override
  State<FirmwareUpdatePage> createState() => _FirmwareUpdatePageState();
}

class _FirmwareUpdatePageState extends State<FirmwareUpdatePage> {
  // Mock states: 'up_to_date', 'available', 'downloading', 'installing'
  String _state = 'available';
  double _progress = 0.0;

  void _startUpdate() {
    setState(() {
      _state = 'downloading';
      _progress = 0.0;
    });
    // Simulate progress
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _progress = 0.3);
    });
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _progress = 0.6);
    });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _state = 'installing';
          _progress = 0.8;
        });
      }
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _state = 'up_to_date';
          _progress = 1.0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Firmware Update')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Version info
          Text('Current version', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  title: const Text('Installed'),
                  trailing: Text('v1.0.0',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant)),
                ),
                if (_state == 'available' || _state == 'downloading' || _state == 'installing') ...[
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('Available'),
                    trailing: Text('v1.1.0',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.bold,
                        )),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('Size'),
                    trailing: Text('1.2 MB',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: colors.onSurfaceVariant)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Changelog
          if (_state != 'up_to_date') ...[
            Text("What's new in v1.1.0", style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ChangelogItem('Improved voice activity detection (VAD)'),
                    _ChangelogItem('Better Wi-Fi reconnect'),
                    _ChangelogItem('Bug fixes'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Progress / action
          if (_state == 'downloading' || _state == 'installing') ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _state == 'downloading'
                              ? 'Downloading...'
                              : 'Installing...',
                          style: theme.textTheme.titleSmall,
                        ),
                        Text('${(_progress * 100).round()}%',
                            style: theme.textTheme.bodyMedium),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: _progress),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.warning_amber,
                            size: 16, color: colors.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Do not power off your device during update.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ] else if (_state == 'available') ...[
            FilledButton.icon(
              onPressed: _startUpdate,
              icon: const Icon(Icons.system_update),
              label: const Text('Update Now'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ] else ...[
            Card(
              color: colors.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: colors.onPrimaryContainer),
                    const SizedBox(width: 12),
                    Text(
                      'Firmware is up to date',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChangelogItem extends StatelessWidget {
  final String text;
  const _ChangelogItem(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('  \u2022  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
