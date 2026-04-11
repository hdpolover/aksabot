import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/api.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/local/local_device.dart';
import '../../../../core/local/local_device_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/success_screen.dart';
import '../../domain/repositories/devices_repository.dart';

/// Registers a locally-provisioned Aksabot device with the AI backend.
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

      setState(() => _phase = _Phase.sendingToken);

      final ip = widget.device.localIp;
      if (ip == null) {
        throw Exception(
          'Device IP not known. Find the device on network first.',
        );
      }

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
      ));
      // Send token + backend WS URL so the device knows where to connect
      final wsUrl = '${ApiConstants.baseUrl.replaceFirst('http', 'ws')}/ws';
      await dio.post('http://$ip/token', data: {
        'token': token,
        'backendUrl': wsUrl,
      });

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
        duration: AppConstants.animNormal,
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
    final appColors = theme.extension<AppColors>()!;
    final hasIp = widget.device.localIp != null;

    return SingleChildScrollView(
      key: const ValueKey('idle'),
      padding: const EdgeInsets.all(AppConstants.spacingXxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(AppConstants.radiusXl),
              ),
              child: Icon(Icons.cloud_queue, size: 40, color: colors.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: AppConstants.spacingXxl),
          Text(
            'Connect to AI cloud',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            'Link your Aksabot to the AI backend to enable voice, memory, reminders, and all AI features.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppConstants.spacingXxl),

          // Device summary
          Material(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spacingLg),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    ),
                    child: Icon(Icons.smart_toy_rounded,
                        color: colors.onPrimaryContainer, size: 22),
                  ),
                  const SizedBox(width: AppConstants.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.device.name, style: theme.textTheme.titleSmall),
                        const SizedBox(height: AppConstants.spacingXxs),
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
                    color: hasIp ? appColors.success : colors.error,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),

          // Warning if no IP
          if (!hasIp) ...[
            Container(
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: colors.onErrorContainer),
                  const SizedBox(width: AppConstants.spacingMd),
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
            const SizedBox(height: AppConstants.spacingMd),
          ],

          // Features unlocked
          _FeatureList(),
          const SizedBox(height: AppConstants.spacingXxxl),

          FilledButton.icon(
            onPressed: hasIp ? _doRegister : null,
            icon: const Icon(Icons.link),
            label: const Text('Register with AI Cloud'),
          ),
          const SizedBox(height: AppConstants.spacingSm),
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
        padding: const EdgeInsets.all(AppConstants.spacingHuge),
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
            const SizedBox(height: AppConstants.spacingXxl),
            Text(label, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppConstants.spacingXs),
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
    final name = _registeredName ?? widget.device.name;

    return SuccessScreen(
      key: const ValueKey('done'),
      title: '$name is connected!',
      subtitle: 'Your Aksabot is now registered with the AI backend. '
          'Voice conversations, memory, and all AI features are ready.',
      onPressed: () => Navigator.of(context).pop(true),
    );
  }

  // ── Error ────────────────────────────────────────────────

  Widget _buildErrorBody() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      key: const ValueKey('error'),
      padding: const EdgeInsets.all(AppConstants.spacingXxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.error_outline_rounded, size: AppConstants.iconHuge, color: colors.error),
          const SizedBox(height: AppConstants.spacingLg),
          Text('Registration failed',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            _error ?? 'An unexpected error occurred.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppConstants.spacingXxxl),
          FilledButton.tonal(
            onPressed: _doRegister,
            child: const Text('Try Again'),
          ),
          const SizedBox(height: AppConstants.spacingSm),
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
// Feature list
// ---------------------------------------------------------------------------

class _FeatureList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    const features = [
      (Icons.record_voice_over_outlined, 'Voice conversations'),
      (Icons.psychology_outlined, 'Persistent memory'),
      (Icons.notifications_active_outlined, 'Reminders & Pomodoro'),
      (Icons.self_improvement_outlined, 'Focus & presence'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('You unlock:',
            style: theme.textTheme.titleSmall
                ?.copyWith(color: colors.onSurfaceVariant)),
        const SizedBox(height: AppConstants.spacingMd),
        for (final f in features)
          Padding(
            padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
            child: Row(
              children: [
                Icon(f.$1, size: 18, color: colors.primary),
                const SizedBox(width: AppConstants.spacingMd),
                Text(f.$2, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
      ],
    );
  }
}
