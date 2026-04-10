import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/local/local_device.dart';
import '../../../../core/local/local_device_store.dart';
import '../../domain/repositories/devices_repository.dart';

/// Registers a locally-provisioned Aksabot device with the AI backend.
///
/// Flow:
///   1. Creates a device record on the backend (gets deviceToken)
///   2. POSTs the token to the ESP32 via HTTP (requires localIp from mDNS)
///   3. Removes the LocalDevice from local store
///   4. Returns true so the caller knows to reload backend devices
///
/// Requires: [device.localIp] must be set (via mDNS discovery first).
class CloudRegisterPage extends StatefulWidget {
  final LocalDevice device;
  const CloudRegisterPage({super.key, required this.device});

  @override
  State<CloudRegisterPage> createState() => _CloudRegisterPageState();
}

enum _Phase { idle, registering, sendingToken, done, error }

class _CloudRegisterPageState extends State<CloudRegisterPage> {
  _Phase _phase = _Phase.idle;
  String? _error;
  String? _registeredName;

  Future<void> _doRegister() async {
    setState(() {
      _phase = _Phase.registering;
      _error = null;
    });

    try {
      // 1. Create device on backend
      final result = await sl<DevicesRepository>().createDevice(
        name: widget.device.name,
      );

      String? token;
      result.fold(
        (failure) => throw Exception(failure.toString()),
        (device) {
          token = device.deviceToken;
          _registeredName = device.name;
        },
      );

      if (token == null || token!.isEmpty) {
        throw Exception('No device token returned from backend.');
      }

      // 2. Deliver token to ESP32 via HTTP (same local network)
      setState(() => _phase = _Phase.sendingToken);

      final ip = widget.device.localIp;
      if (ip == null) {
        throw Exception(
          'Device IP not known. Find the device on network first '
          '(use "Find device on network" on the home screen).',
        );
      }

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
      ));
      await dio.post('http://$ip/token', data: {'token': token});

      // 3. Remove local record — backend now owns this device
      await LocalDeviceStore.remove(widget.device.id);

      setState(() => _phase = _Phase.done);
    } on DioException catch (e) {
      setState(() {
        _phase = _Phase.error;
        _error = e.type == DioExceptionType.connectionError ||
                e.type == DioExceptionType.connectionTimeout
            ? 'Could not reach your Aksabot. Make sure your phone is on '
              'the same Wi-Fi network as the device.'
            : 'Network error: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _phase = _Phase.error;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canClose =
        _phase == _Phase.idle || _phase == _Phase.error || _phase == _Phase.done;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to AI Cloud'),
        leading: canClose
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () =>
                    Navigator.of(context).pop(_phase == _Phase.done),
              )
            : null,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.idle:
        return _buildIdleBody();
      case _Phase.registering:
        return _buildProgressBody(
          icon: Icons.cloud_upload_outlined,
          label: 'Creating device profile...',
          sublabel: 'Registering with backend',
        );
      case _Phase.sendingToken:
        return _buildProgressBody(
          icon: Icons.send_to_mobile_outlined,
          label: 'Sending to your Aksabot...',
          sublabel: 'Delivering authentication token',
        );
      case _Phase.done:
        return _buildDoneBody();
      case _Phase.error:
        return _buildErrorBody();
    }
  }

  // ── Idle ────────────────────────────────────────────────

  Widget _buildIdleBody() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasIp = widget.device.localIp != null;

    return SingleChildScrollView(
      key: const ValueKey('idle'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.cloud_queue, size: 72, color: colors.primary),
          const SizedBox(height: 24),
          Text(
            'Connect to AI cloud',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Link your Aksabot to the AI backend to enable voice '
            'conversations, memory, reminders, and all AI features.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),

          // Device summary card
          Card(
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
                    child: Icon(Icons.smart_toy_rounded,
                        color: colors.onPrimaryContainer),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.device.name,
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          hasIp
                              ? 'Found at ${widget.device.localIp}'
                              : 'Device IP not known',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: hasIp ? colors.onSurfaceVariant : colors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    hasIp ? Icons.check_circle_outline : Icons.warning_amber,
                    color: hasIp ? Colors.green : colors.error,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Warning if no IP
          if (!hasIp) ...[
            Card(
              color: colors.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: colors.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Use "Find device on network" on the home screen first.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Feature list
          _FeatureCard(),
          const SizedBox(height: 32),

          FilledButton.icon(
            onPressed: hasIp ? _doRegister : null,
            icon: const Icon(Icons.link),
            label: const Text('Register with AI Cloud'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }

  // ── Progress ────────────────────────────────────────────

  Widget _buildProgressBody({
    required IconData icon,
    required String label,
    required String sublabel,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      key: ValueKey(label),
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                      strokeWidth: 3, color: colors.primary),
                ),
                Icon(icon, size: 36, color: colors.primary),
              ],
            ),
            const SizedBox(height: 24),
            Text(label, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(sublabel,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  // ── Done ────────────────────────────────────────────────

  Widget _buildDoneBody() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final name = _registeredName ?? widget.device.name;

    return Padding(
      key: const ValueKey('done'),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle_rounded, size: 80, color: Colors.green),
          const SizedBox(height: 24),
          Text(
            '$name is connected!',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Your Aksabot is now registered with the AI backend. '
            'Voice conversations, memory, and all AI features are ready.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 48),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // ── Error ────────────────────────────────────────────────

  Widget _buildErrorBody() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      key: const ValueKey('error'),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.error_outline_rounded, size: 64, color: colors.error),
          const SizedBox(height: 16),
          Text('Registration failed',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            _error ?? 'An unexpected error occurred.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 32),
          FilledButton.tonal(
            onPressed: _doRegister,
            child: const Text('Try Again'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feature card
// ---------------------------------------------------------------------------

class _FeatureCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    const features = [
      (Icons.record_voice_over_outlined, 'Voice conversations with AI'),
      (Icons.psychology_outlined, 'Persistent memory across sessions'),
      (Icons.notifications_active_outlined, 'Smart reminders & Pomodoro'),
      (Icons.self_improvement_outlined, 'Focus mode & presence detection'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You unlock:',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: colors.onSurfaceVariant)),
            const SizedBox(height: 10),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(f.$1, size: 18, color: colors.primary),
                    const SizedBox(width: 12),
                    Text(f.$2, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
