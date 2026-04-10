import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../../../../core/di/injection.dart';
import '../../domain/repositories/devices_repository.dart';
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
            'Choose a connection method to pair your Aksabot device.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),

          // Option 1: Wi-Fi (SoftAP)
          _ConnectionOption(
            icon: Icons.wifi,
            title: 'Wi-Fi',
            description:
                'Connect to your Aksabot\'s hotspot and enter your '
                'home Wi-Fi credentials. No Bluetooth required.',
            tag: 'Easy setup',
            tagColor: colors.primary,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _WifiSetupPage()),
            ),
          ),
          const SizedBox(height: 16),

          // Option 2: Bluetooth
          _ConnectionOption(
            icon: Icons.bluetooth,
            title: 'Bluetooth',
            description:
                'Scan for nearby Aksabot devices and configure Wi-Fi '
                'credentials over BLE. Requires Bluetooth permission.',
            tag: 'Recommended',
            tagColor: colors.primary,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BleProvisioningPage()),
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
// 4. App creates device on backend → gets deviceToken
// 5. App sends SSID + password + deviceToken to ESP32 via HTTP (192.168.4.1)
// 6. ESP32 stores creds, switches to station mode, connects to home Wi-Fi
// 7. ESP32 connects to backend via WebSocket using the token
// 8. Device appears online in the app
// ---------------------------------------------------------------------------

class _WifiSetupPage extends StatefulWidget {
  const _WifiSetupPage();

  @override
  State<_WifiSetupPage> createState() => _WifiSetupPageState();
}

class _WifiSetupPageState extends State<_WifiSetupPage> {
  final _pageController = PageController();
  int _step = 0;

  // Step 2: Wi-Fi credentials
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController(text: 'My Aksabot');
  bool _obscurePassword = true;

  // Step 3: provisioning
  bool _isProvisioning = false;
  String? _error;
  List<_ProvisionStep> _provisionSteps = [];

  // ESP32 SoftAP address
  static const _espBaseUrl = 'http://192.168.4.1';

  @override
  void dispose() {
    _pageController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
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

  Future<void> _startProvisioning() async {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();

    if (ssid.isEmpty) {
      setState(() => _error = 'Please enter your Wi-Fi network name');
      return;
    }

    setState(() {
      _isProvisioning = true;
      _error = null;
      _provisionSteps = [
        _ProvisionStep('Registering device...', _StepState.loading),
        _ProvisionStep('Sending Wi-Fi credentials', _StepState.pending),
        _ProvisionStep('Waiting for device to connect', _StepState.pending),
      ];
    });
    _goToStep(2);

    // Step 1: Create device on backend
    final repo = sl<DevicesRepository>();
    final result = await repo.createDevice(name: name.isEmpty ? 'My Aksabot' : name);

    final device = result.fold(
      (failure) {
        _setProvisionError(0, failure.message);
        return null;
      },
      (device) => device,
    );

    if (device == null) return;

    _updateProvisionStep(0, _StepState.done);
    _updateProvisionStep(1, _StepState.loading);

    // Step 2: Send Wi-Fi credentials + device token to ESP32 via SoftAP HTTP
    try {
      final dio = Dio(BaseOptions(
        baseUrl: _espBaseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
      ));

      await dio.post('/provision', data: {
        'ssid': ssid,
        'password': password,
        'deviceId': device.id,
        if (device.deviceToken != null) 'deviceToken': device.deviceToken,
      });

      _updateProvisionStep(1, _StepState.done);
      _updateProvisionStep(2, _StepState.loading);

      // Step 3: Wait for the ESP32 to connect to Wi-Fi and appear online
      // Poll the backend to check if the device comes online
      bool online = false;
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;

        final check = await repo.getDevice(device.id);
        final isOnline = check.fold((_) => false, (d) => d.isOnline);
        if (isOnline) {
          online = true;
          break;
        }
      }

      if (online) {
        _updateProvisionStep(2, _StepState.done);
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) _goToStep(3); // Success
      } else {
        _setProvisionError(
          2,
          'Device didn\'t come online within 60 seconds. '
          'Check that your Wi-Fi credentials are correct.',
        );
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        _setProvisionError(
          1,
          'Could not reach the device. Make sure you\'re connected '
          'to the "Aksabot-XXXX" Wi-Fi hotspot.',
        );
      } else {
        _setProvisionError(1, 'Failed to send credentials: ${e.message}');
      }
    } catch (e) {
      _setProvisionError(1, 'Unexpected error: $e');
    }
  }

  void _updateProvisionStep(int index, _StepState state) {
    if (!mounted) return;
    setState(() {
      _provisionSteps[index] = _ProvisionStep(
        _provisionSteps[index].label,
        state,
      );
    });
  }

  void _setProvisionError(int failedStep, String message) {
    if (!mounted) return;
    setState(() {
      _isProvisioning = false;
      _provisionSteps[failedStep] = _ProvisionStep(
        _provisionSteps[failedStep].label,
        _StepState.error,
      );
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Wi-Fi Setup${_step > 0 ? ' — Step ${_step + 1}/4' : ''}'),
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildConnectHotspotStep(),
          _buildCredentialsStep(),
          _buildProvisioningStep(),
          _buildSuccessStep(),
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
            'Connect to your Aksabot',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 16),

          // Instruction card
          Card(
            color: colors.primaryContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InstructionRow(
                    number: '1',
                    text: 'Make sure your Aksabot is powered on',
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
                    text: 'Come back to this app',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'The device creates a temporary hotspot for setup. '
            'After setup, it will connect to your home Wi-Fi.',
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

  // ── Step 2: Enter Wi-Fi credentials ──────────────────────────

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
            'Enter your Wi-Fi credentials',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Your Aksabot will use these to connect to your home network.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _ssidController,
            decoration: const InputDecoration(
              labelText: 'Wi-Fi network name',
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
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Device name',
              prefixIcon: Icon(Icons.smart_toy_outlined),
              hintText: 'My Aksabot',
            ),
            textCapitalization: TextCapitalization.words,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: colors.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isProvisioning ? null : _startProvisioning,
            child: const Text('Set Up Device'),
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

  // ── Step 3: Provisioning progress ────────────────────────────

  Widget _buildProvisioningStep() {
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
          const SizedBox(height: 32),
          ..._provisionSteps.map((step) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    _stepIcon(step.state, colors),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        step.label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: step.state == _StepState.pending
                              ? colors.onSurfaceVariant
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
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
                _goToStep(1); // Back to credentials
              },
              child: const Text('Try Again'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepIcon(_StepState state, ColorScheme colors) {
    switch (state) {
      case _StepState.done:
        return const Icon(Icons.check_circle, color: Colors.green, size: 24);
      case _StepState.loading:
        return SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.primary,
          ),
        );
      case _StepState.error:
        return Icon(Icons.cancel, color: colors.error, size: 24);
      case _StepState.pending:
        return Icon(Icons.circle_outlined, color: colors.outline, size: 24);
    }
  }

  // ── Step 4: Success ──────────────────────────────────────────

  Widget _buildSuccessStep() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle, size: 64, color: Colors.green),
          const SizedBox(height: 16),
          Text(
            "You're all set!",
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_nameController.text.trim()} is connected to Wi-Fi and '
            'ready to use.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(); // pop wifi flow
              context.pop(); // pop add-device route
            },
            child: const Text('Go to Dashboard'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper models
// ---------------------------------------------------------------------------

enum _StepState { pending, loading, done, error }

class _ProvisionStep {
  final String label;
  final _StepState state;
  const _ProvisionStep(this.label, this.state);
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

// ---------------------------------------------------------------------------
// Connection option card (shared between Wi-Fi and Bluetooth)
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
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: tagColor,
                            ),
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
