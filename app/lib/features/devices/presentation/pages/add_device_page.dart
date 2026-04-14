import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/local/local_device_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/step_progress_bar.dart';
import '../../../../core/widgets/success_screen.dart';
import 'ble_provisioning_page.dart';

/// Add Device screen — choose between Bluetooth or Wi-Fi SoftAP.
class AddDevicePage extends StatelessWidget {
  const AddDevicePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Device')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingXxl),
          child: Column(
            children: [
              const Spacer(),
              // Hero icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                ),
                child: Icon(
                  Icons.smart_toy_rounded,
                  size: 40,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: AppConstants.spacingXxl),
              Text(
                'How do you want to connect?',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppConstants.spacingSm),
              Text(
                'Choose how your phone will talk to your Aksabot.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const Spacer(),

              // Bluetooth option (primary)
              _ConnectionOption(
                icon: Icons.bluetooth,
                title: 'Bluetooth',
                subtitle: 'Scan nearby and send Wi-Fi credentials over BLE',
                isPrimary: true,
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(builder: (_) => const BleProvisioningPage()),
                ),
              ),
              const SizedBox(height: AppConstants.spacingMd),

              // Wi-Fi option (secondary)
              _ConnectionOption(
                icon: Icons.wifi_tethering,
                title: 'Wi-Fi Hotspot',
                subtitle: 'Connect to Aksabot hotspot manually',
                isPrimary: false,
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(builder: (_) => const _WifiSetupPage()),
                ),
              ),
              const SizedBox(height: AppConstants.spacingXxl),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connection option tile
// ---------------------------------------------------------------------------

class _ConnectionOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isPrimary;
  final VoidCallback onTap;

  const _ConnectionOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: isPrimary
          ? colors.primaryContainer
          : colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spacingLg),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isPrimary
                      ? colors.primary.withValues(alpha: 0.15)
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Icon(
                  icon,
                  color: isPrimary ? colors.primary : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppConstants.spacingLg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title, style: theme.textTheme.titleSmall),
                        if (isPrimary) ...[
                          const SizedBox(width: AppConstants.spacingSm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppConstants.spacingSm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius:
                                  BorderRadius.circular(AppConstants.radiusFull),
                            ),
                            child: Text(
                              'Recommended',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onPrimary,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppConstants.spacingXxs),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isPrimary
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: AppConstants.iconSm,
                color: isPrimary
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wi-Fi SoftAP setup flow
// ---------------------------------------------------------------------------

class _WifiSetupPage extends StatefulWidget {
  const _WifiSetupPage();

  @override
  State<_WifiSetupPage> createState() => _WifiSetupPageState();
}

class _WifiSetupPageState extends State<_WifiSetupPage> {
  final _pageController = PageController();
  int _step = 0;

  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  bool _isSending = false;
  String? _error;
  _SendState _sendState = _SendState.idle;

  static const _espBaseUrl = 'http://192.168.4.1';

  @override
  void dispose() {
    _pageController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    _pageController.animateToPage(
      step,
      duration: AppConstants.animNormal,
      curve: Curves.easeInOut,
    );
    setState(() => _step = step);
  }

  Future<void> _sendCredentials() async {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text;

    if (ssid.isEmpty) {
      setState(() => _error = 'Please enter your Wi-Fi network name');
      return;
    }

    setState(() {
      _isSending = true;
      _error = null;
      _sendState = _SendState.sending;
    });
    _goToStep(2);

    try {
      final dio = Dio(BaseOptions(
        baseUrl: _espBaseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
      ));

      await dio.post('/provision', data: {
        'ssid': ssid,
        'password': password,
      });

      setState(() => _sendState = _SendState.waiting);
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;

      final device = LocalDeviceStore.create(
        name: 'Aksabot',
        ssid: _ssidController.text.trim(),
      );
      await LocalDeviceStore.save(device);

      setState(() {
        _isSending = false;
        _sendState = _SendState.done;
      });
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) _goToStep(3);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _sendState = _SendState.idle;
      });

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        _showSendError(
          'Could not reach the device. Make sure your phone is connected '
          'to the "Aksabot-XXXX" Wi-Fi hotspot.',
        );
      } else {
        _showSendError('Failed to send credentials: ${e.message}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _sendState = _SendState.idle;
      });
      _showSendError('Unexpected error: $e');
    }
  }

  void _showSendError(String message) {
    setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final stepLabels = ['Hotspot', 'Credentials', 'Sending', 'Done'];

    return Scaffold(
      appBar: AppBar(
        title: Text('Wi-Fi Setup — ${stepLabels[_step.clamp(0, 3)]}'),
      ),
      body: Column(
        children: [
          StepProgressBar(current: _step, total: 4),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildConnectHotspotStep(),
                _buildCredentialsStep(),
                _buildSendingStep(),
                _buildSuccessStep(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 1: Connect to hotspot ──────────────────────────────

  Widget _buildConnectHotspotStep() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.spacingXxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.wifi_tethering, size: AppConstants.iconMassive, color: colors.primary),
          const SizedBox(height: AppConstants.spacingLg),
          Text(
            'Connect to your Aksabot hotspot',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppConstants.spacingXxl),

          // Instruction steps
          for (final (i, text) in [
            'Power on your Aksabot',
            'Open your phone\'s Wi-Fi settings',
            'Connect to "Aksabot-XXXX"',
            'Return to this app',
          ].indexed) ...[
            _InstructionRow(number: '${i + 1}', text: text),
            if (i < 3) const SizedBox(height: AppConstants.spacingLg),
          ],

          const SizedBox(height: AppConstants.spacingXxl),
          Text(
            'The hotspot is temporary — after setup your device will connect to your home Wi-Fi.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppConstants.spacingXxl),
          FilledButton(
            onPressed: () => _goToStep(1),
            child: const Text("I'm connected"),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Enter credentials ───────────────────────────────

  Widget _buildCredentialsStep() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.spacingXxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.wifi_lock, size: AppConstants.iconXxl, color: colors.primary),
          const SizedBox(height: AppConstants.spacingLg),
          Text(
            'Enter your home Wi-Fi',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            'Your Aksabot will use these to connect to the internet.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppConstants.spacingXxl),
          TextField(
            controller: _ssidController,
            decoration: const InputDecoration(
              labelText: 'Wi-Fi network name (SSID)',
              prefixIcon: Icon(Icons.wifi),
            ),
          ),
          const SizedBox(height: AppConstants.spacingLg),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Wi-Fi password',
              prefixIcon: const Icon(Icons.lock_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppConstants.spacingMd),
            Text(_error!, style: TextStyle(color: colors.error)),
          ],
          const SizedBox(height: AppConstants.spacingXxl),
          FilledButton(
            onPressed: _isSending ? null : _sendCredentials,
            child: const Text('Send to Device'),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          TextButton(
            onPressed: () => _goToStep(0),
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }

  // ── Step 3: Sending progress ────────────────────────────────

  Widget _buildSendingStep() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(AppConstants.spacingXxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Setting up your device...',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppConstants.spacingHuge),
          _ProgressItem(
            label: 'Sending credentials to device',
            state: _sendState == _SendState.sending
                ? _ItemState.loading
                : (_sendState == _SendState.idle
                    ? _ItemState.pending
                    : _ItemState.done),
          ),
          const SizedBox(height: AppConstants.spacingLg),
          _ProgressItem(
            label: 'Device connecting to Wi-Fi',
            state: _sendState == _SendState.waiting
                ? _ItemState.loading
                : (_sendState == _SendState.done
                    ? _ItemState.done
                    : _ItemState.pending),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppConstants.spacingXxl),
            Container(
              padding: const EdgeInsets.all(AppConstants.spacingLg),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
              child: Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onErrorContainer,
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacingLg),
            FilledButton.tonal(
              onPressed: () {
                setState(() => _error = null);
                _goToStep(1);
              },
              child: const Text('Try Again'),
            ),
          ],
        ],
      ),
    );
  }

  // ── Step 4: Success ─────────────────────────────────────────

  Widget _buildSuccessStep() {
    final ssid = _ssidController.text.trim();

    return SuccessScreen(
      title: 'Device connected!',
      subtitle: ssid.isNotEmpty
          ? 'Your Aksabot is now connected to "$ssid".'
          : 'Your Aksabot is connected to the internet.',
      hint: 'Connect to backend later to unlock AI features',
      onPressed: () => Navigator.of(context).pop(),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper models & widgets
// ---------------------------------------------------------------------------

enum _SendState { idle, sending, waiting, done }

enum _ItemState { pending, loading, done }

class _ProgressItem extends StatelessWidget {
  final String label;
  final _ItemState state;

  const _ProgressItem({required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final appColors = theme.extension<AppColors>()!;

    Widget leading;
    switch (state) {
      case _ItemState.done:
        leading = Icon(Icons.check_circle, color: appColors.success, size: AppConstants.iconLg);
      case _ItemState.loading:
        leading = SizedBox(
          width: AppConstants.iconLg,
          height: AppConstants.iconLg,
          child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
        );
      case _ItemState.pending:
        leading = Icon(Icons.circle_outlined, color: colors.outline, size: AppConstants.iconLg);
    }

    return Row(
      children: [
        leading,
        const SizedBox(width: AppConstants.spacingMd),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: state == _ItemState.pending ? colors.onSurfaceVariant : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _InstructionRow extends StatelessWidget {
  final String number;
  final String text;
  const _InstructionRow({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onPrimaryContainer,
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
