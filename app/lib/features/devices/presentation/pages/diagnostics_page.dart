import 'package:flutter/material.dart';

/// Diagnostics screen — planned UI.
class DiagnosticsPage extends StatefulWidget {
  final String deviceId;
  const DiagnosticsPage({super.key, required this.deviceId});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  bool _testing = false;
  Map<String, _TestResult>? _results;

  void _runTest() async {
    setState(() {
      _testing = true;
      _results = null;
    });

    // Simulate connection test
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    setState(() {
      _testing = false;
      _results = {
        'Backend API': _TestResult(true, '42ms'),
        'WebSocket': _TestResult(true, 'connected'),
        'BLE': _TestResult(false, 'not connected'),
        'Wi-Fi (ESP32)': _TestResult(true, '-55 dBm'),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Connection test
          Text('Connection Test', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_results != null)
                    ...(_results!.entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              e.value.passed
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: e.value.passed
                                  ? Colors.green
                                  : colors.error,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(e.key)),
                            Text(
                              e.value.detail,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: _testing ? null : _runTest,
                    child: Text(_testing ? 'Testing...' : 'Run Test'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Audio pipeline test
          Text('Audio Pipeline Test', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.tonal(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Audio pipeline test not yet implemented')),
                      );
                    },
                    child: const Text('Test Mic \u2192 STT \u2192 LLM \u2192 TTS \u2192 Speaker'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Last test: not run',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Device logs
          Text('Device Logs', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Container(
              height: 200,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  '[14:23:01] WebSocket connected\n'
                  '[14:23:02] Audio session started\n'
                  '[14:23:05] STT: "hello there"\n'
                  '[14:23:06] LLM streaming response\n'
                  '[14:23:07] TTS: 2 chunks encoded\n'
                  '[14:23:08] Audio playback complete\n'
                  '[14:23:10] Session idle\n',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Log export not yet implemented')),
              );
            },
            child: const Text('Export Logs'),
          ),
          const SizedBox(height: 32),

          // Factory reset
          OutlinedButton.icon(
            onPressed: () => _confirmFactoryReset(context),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Factory Reset Device'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.error,
              side: BorderSide(color: colors.error),
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmFactoryReset(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Factory Reset'),
        content: const Text(
          'This will erase all device configuration, revoke its token, '
          'and remove it from your account. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Factory reset not yet implemented')),
              );
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

class _TestResult {
  final bool passed;
  final String detail;
  const _TestResult(this.passed, this.detail);
}
