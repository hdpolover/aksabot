import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../../../../core/local/local_device_store.dart';
import 'ble_provisioning_page.dart';

/// Add Device screen — choose between Wi-Fi (SoftAP) or Bluetooth.
class AddDevicePage extends StatelessWidget {
  const AddDevicePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Device')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Header
          Icon(Icons.smart_toy_rounded, size: 64, color: colors.primary),
          const SizedBox(height: 16),
          Text(
            'How do you want to connect?',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose how your phone will talk to your Aksabot device.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),

          // Option 1: Bluetooth (primary)
          _ConnectionOption(
            icon: Icons.bluetooth,
            title: 'Bluetooth',
            description:
                'Scan for your Aksabot nearby and send Wi-Fi credentials '
                'over BLE. The recommended way to set up a new device.',
            tag: 'Recommended',
            tagColor: colors.primary,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BleProvisioningPage()),
            ),
          ),
          const SizedBox(height: 16),

          // Option 2: Wi-Fi SoftAP
          _ConnectionOption(
            icon: Icons.wifi_tethering,
            title: 'Wi-Fi Hotspot',
            description:
                'Connect your phone to the Aksabot hotspot and send '
                'credentials over Wi-Fi. Use this if Bluetooth is unavailable.',
            tag: 'Alternative',
            tagColor: colors.secondary,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _WifiSetupPage()),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wi-Fi SoftAP flow
// ---------------------------------------------------------------------------
//
// How it works:
// 1. ESP32 boots in AP mode, creating hotspot "Aksabot-XXXX"
// 2. User connects phone to that hotspot (in phone Settings)
// 3. In the app, user enters home Wi-Fi SSID + password
// 4. App POSTs credentials to ESP32 at http://192.168.4.1/provision
// 5. ESP32 stores creds, switches to station mode, connects to home Wi-Fi
//
// Note: No backend registration is required for initial setup.
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

  // ESP32 SoftAP address
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
      duration: const Duration(milliseconds: 300),
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

      // Credentials accepted — give device a moment to process
      setState(() => _sendState = _SendState.waiting);
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;

      // Persist locally so the home screen shows this device immediately
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
    // Stay on progress step so error is visible
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
          _StepProgressBar(current: _step, total: 4),
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

  // ── Step 1: Connect to hotspot ───────────────────────────────

  Widget _buildConnectHotspotStep() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.wifi_tethering, size: 48, color: colors.primary),
          const SizedBox(height: 16),
          Text(
            'Connect to your Aksabot hotspot',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 16),

          Card(
            color: colors.primaryContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InstructionRow(
                    number: '1',
                    text: 'Power on your Aksabot',
                  ),
                  const SizedBox(height: 12),
                  _InstructionRow(
                    number: '2',
                    text: 'Open your phone\'s Wi-Fi settings',
                  ),
                  const SizedBox(height: 12),
                  _InstructionRow(
                    number: '3',
                    text: 'Connect to the network named "Aksabot-XXXX"',
                  ),
                  const SizedBox(height: 12),
                  _InstructionRow(
                    number: '4',
                    text: 'Return to this app',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Aksabot creates a temporary hotspot for setup only. '
            'After setup it will connect to your home Wi-Fi.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => _goToStep(1),
            child: const Text("I'm connected to Aksabot-XXXX"),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Enter credentials ────────────────────────────────

  Widget _buildCredentialsStep() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.wifi_lock, size: 48, color: colors.primary),
          const SizedBox(height: 16),
          Text(
            'Enter your home Wi-Fi',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Your Aksabot will use these to connect to the internet.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _ssidController,
            decoration: const InputDecoration(
              labelText: 'Wi-Fi network name (SSID)',
              prefixIcon: Icon(Icons.wifi),
            ),
          ),
          const SizedBox(height: 16),
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
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: colors.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isSending ? null : _sendCredentials,
            child: const Text('Send to Device'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _goToStep(0),
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }

  // ── Step 3: Sending progress ─────────────────────────────────

  Widget _buildSendingStep() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Setting up your device...',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 40),
          _ProgressItem(
            label: 'Sending credentials to device',
            state: _sendState == _SendState.sending
                ? _ItemState.loading
                : (_sendState == _SendState.idle
                    ? _ItemState.pending
                    : _ItemState.done),
          ),
          const SizedBox(height: 16),
          _ProgressItem(
            label: 'Device connecting to Wi-Fi',
            state: _sendState == _SendState.waiting
                ? _ItemState.loading
                : (_sendState == _SendState.done
                    ? _ItemState.done
                    : _ItemState.pending),
          ),
          if (_error != null) ...[
            const SizedBox(height: 24),
            Card(
              color: colors.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onErrorContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
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

  // ── Step 4: Success ──────────────────────────────────────────

  Widget _buildSuccessStep() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ssid = _ssidController.text.trim();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 72,
            color: Colors.green,
          ),
          const SizedBox(height: 20),
          Text(
            "Device connected!",
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            ssid.isNotEmpty
                ? 'Your Aksabot is now connected to "$ssid".'
                : 'Your Aksabot is connected to the internet.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: colors.onSecondaryContainer),
                  const SizedBox(width: 6),
                  Text(
                    'Connect to backend later to unlock AI features',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper models & widgets shared by both flows
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

    Widget leading;
    switch (state) {
      case _ItemState.done:
        leading = const Icon(Icons.check_circle, color: Colors.green, size: 24);
        break;
      case _ItemState.loading:
        leading = SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
        );
        break;
      case _ItemState.pending:
        leading = Icon(Icons.circle_outlined, color: colors.outline, size: 24);
        break;
    }

    return Row(
      children: [
        leading,
        const SizedBox(width: 12),
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
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: colors.primary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

class _StepProgressBar extends StatelessWidget {
  final int current;
  final int total;

  const _StepProgressBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: List.generate(total, (index) {
          final active = index <= current;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: index < total - 1 ? 4 : 0),
              height: 4,
              decoration: BoxDecoration(
                color: active ? colors.primary : colors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connection option card
// ---------------------------------------------------------------------------

class _ConnectionOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String tag;
  final Color tagColor;
  final VoidCallback onTap;

  const _ConnectionOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.tag,
    required this.tagColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: tagColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tag,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: tagColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
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
  }
}
