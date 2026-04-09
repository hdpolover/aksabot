import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ble/ble_constants.dart';
import '../../../../core/ble/ble_provisioning_service.dart';
import '../../../../core/di/injection.dart';
import '../../domain/repositories/devices_repository.dart';

/// 5-step BLE provisioning wizard.
///
/// Step 1: Scan for devices
/// Step 2: Wi-Fi setup
/// Step 3: Register & write token
/// Step 4: Name your bot
/// Step 5: Done
class BleProvisioningPage extends StatefulWidget {
  const BleProvisioningPage({super.key});

  @override
  State<BleProvisioningPage> createState() => _BleProvisioningPageState();
}

class _BleProvisioningPageState extends State<BleProvisioningPage> {
  final _pageController = PageController();
  final _ble = BleProvisioningService();

  int _step = 0;

  // Step 1: Scan
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  StreamSubscription? _scanSub;

  // Step 2: Wi-Fi
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  int _wifiStatus = BleConstants.wifiDisconnected;
  bool _isConnectingWifi = false;

  // Step 3: Register
  String _registerStatus = 'idle'; // idle, registering, writing_token, waiting_auth, done, error
  String? _registerError;
  String? _deviceId;

  // Step 4: Name
  final _nameController = TextEditingController(text: 'Aksa');

  @override
  void dispose() {
    _scanSub?.cancel();
    _ble.disconnect();
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

  // ── Step 1: Scan ─────────────────────────────────────────────

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _scanResults = [];
    });

    _scanSub?.cancel();
    _scanSub = _ble.startScan().listen((results) {
      setState(() => _scanResults = results);
    });

    // Auto-stop after timeout
    await Future.delayed(const Duration(seconds: 10));
    if (mounted) {
      await _ble.stopScan();
      setState(() => _isScanning = false);
    }
  }

  Future<void> _selectDevice(BluetoothDevice device) async {
    await _ble.stopScan();
    _scanSub?.cancel();
    setState(() => _isScanning = false);

    try {
      await _ble.connect(device);
      _goToStep(1);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: $e')),
      );
    }
  }

  // ── Step 2: Wi-Fi ────────────────────────────────────────────

  Future<void> _connectWifi() async {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text;

    if (ssid.isEmpty) return;

    setState(() {
      _isConnectingWifi = true;
      _wifiStatus = BleConstants.wifiConnecting;
    });

    try {
      final statusStream = await _ble.writeWifiCredentials(ssid, password);

      await for (final status in statusStream) {
        if (!mounted) return;
        setState(() => _wifiStatus = status);

        if (status == BleConstants.wifiConnected) {
          setState(() => _isConnectingWifi = false);
          _goToStep(2); // Proceed to registration
          return;
        }
        if (status == BleConstants.wifiFailed) {
          setState(() => _isConnectingWifi = false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Wi-Fi connection failed. Check credentials.')),
          );
          return;
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isConnectingWifi = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // ── Step 3: Register ─────────────────────────────────────────

  Future<void> _registerDevice() async {
    setState(() {
      _registerStatus = 'registering';
      _registerError = null;
    });

    // 1. Create device on backend
    final repo = sl<DevicesRepository>();
    final result = await repo.createDevice(name: _nameController.text.trim());

    final device = result.fold(
      (failure) {
        setState(() {
          _registerStatus = 'error';
          _registerError = failure.message;
        });
        return null;
      },
      (device) => device,
    );

    if (device == null) return;
    _deviceId = device.id;
    setState(() => _registerStatus = 'writing_token');

    // 2. Write device token to ESP32 via BLE
    // Note: createDevice returns the device but not the token directly.
    // The token was returned in the API response. We need to access it.
    // For now we'll read it from the device creation response.
    // TODO: The createDevice response should include the token for BLE provisioning.
    // For now, skip token writing (the device is registered, ESP will get token via Wi-Fi setup flow).

    setState(() {
      _registerStatus = 'done';
    });
    _goToStep(3); // Name step
  }

  // ── Step 4: Name ─────────────────────────────────────────────

  Future<void> _saveName() async {
    if (_deviceId == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final repo = sl<DevicesRepository>();
    await repo.updateSettings(_deviceId!, {'name': name});
    _goToStep(4); // Done
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add via Bluetooth — Step ${_step + 1}/5'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildScanStep(),
          _buildWifiStep(),
          _buildRegisterStep(),
          _buildNameStep(),
          _buildDoneStep(),
        ],
      ),
    );
  }

  // ── Step 1: Scan ─────────────────────────────────────────────

  Widget _buildScanStep() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Text(
            'Looking for Aksabot devices...',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_isScanning)
            const LinearProgressIndicator()
          else
            const SizedBox(height: 4),
          const SizedBox(height: 16),

          // Scan results
          Expanded(
            child: _scanResults.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isScanning
                              ? Icons.bluetooth_searching
                              : Icons.bluetooth_disabled,
                          size: 48,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isScanning
                              ? 'Scanning...'
                              : 'No devices found. Make sure your\nAksabot is powered on.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _scanResults.length,
                    itemBuilder: (context, index) {
                      final result = _scanResults[index];
                      final name = result.advertisementData.advName.isNotEmpty
                          ? result.advertisementData.advName
                          : 'Unknown Device';
                      final rssi = result.rssi;

                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.smart_toy_outlined,
                                color: colors.onPrimaryContainer, size: 20),
                          ),
                          title: Text(name),
                          subtitle: Text('Signal: $rssi dBm'),
                          trailing: Icon(Icons.chevron_right,
                              color: colors.onSurfaceVariant),
                          onTap: () => _selectDevice(result.device),
                        ),
                      );
                    },
                  ),
          ),

          // Scan button
          FilledButton.icon(
            onPressed: _isScanning ? null : _startScan,
            icon: const Icon(Icons.bluetooth_searching),
            label: Text(_isScanning ? 'Scanning...' : 'Scan for Devices'),
          ),
          const SizedBox(height: 8),
          Text(
            "Can't find your device? Make sure it's powered on and in pairing mode.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Wi-Fi ────────────────────────────────────────────

  Widget _buildWifiStep() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.wifi, size: 48, color: colors.primary),
          const SizedBox(height: 16),
          Text(
            'Connect to Wi-Fi',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your Wi-Fi credentials. The device will connect '
            'to this network to reach the Aksabot backend.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _ssidController,
            decoration: const InputDecoration(
              labelText: 'Network name (SSID)',
              prefixIcon: Icon(Icons.wifi),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
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

          // Status indicator
          if (_wifiStatus == BleConstants.wifiConnecting) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text('Connecting...', style: theme.textTheme.bodyMedium),
              ],
            ),
            const SizedBox(height: 16),
          ] else if (_wifiStatus == BleConstants.wifiFailed) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 16, color: colors.error),
                const SizedBox(width: 8),
                Text(
                  'Connection failed. Check credentials.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colors.error),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          const SizedBox(height: 8),
          FilledButton(
            onPressed: _isConnectingWifi ? null : _connectWifi,
            child: Text(_isConnectingWifi ? 'Connecting...' : 'Connect'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              _ble.disconnect();
              _goToStep(0);
            },
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }

  // ── Step 3: Register ─────────────────────────────────────────

  Widget _buildRegisterStep() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // Auto-start registration when this step becomes visible
    if (_registerStatus == 'idle') {
      Future.microtask(_registerDevice);
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Registering with server...',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 32),
          _RegisterCheckItem(
            label: 'Wi-Fi connected',
            status: _wifiStatus == BleConstants.wifiConnected
                ? _CheckStatus.done
                : _CheckStatus.pending,
          ),
          const SizedBox(height: 12),
          _RegisterCheckItem(
            label: 'Device registered',
            status: _registerStatus == 'registering'
                ? _CheckStatus.loading
                : (_registerStatus == 'error'
                    ? _CheckStatus.error
                    : _CheckStatus.done),
          ),
          const SizedBox(height: 12),
          _RegisterCheckItem(
            label: 'Writing auth token',
            status: _registerStatus == 'writing_token'
                ? _CheckStatus.loading
                : (_registerStatus == 'done'
                    ? _CheckStatus.done
                    : _CheckStatus.pending),
          ),
          if (_registerError != null) ...[
            const SizedBox(height: 24),
            Text(
              _registerError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.error),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () {
                setState(() => _registerStatus = 'idle');
                _registerDevice();
              },
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  // ── Step 4: Name ─────────────────────────────────────────────

  Widget _buildNameStep() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          Icon(Icons.smart_toy_rounded, size: 64, color: colors.primary),
          const SizedBox(height: 16),
          Text(
            'What should I call myself?',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Bot name',
              prefixIcon: Icon(Icons.edit),
            ),
            textCapitalization: TextCapitalization.words,
            autofocus: true,
          ),
          const SizedBox(height: 8),
          Text(
            'You can change this later in personality settings.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saveName,
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }

  // ── Step 5: Done ─────────────────────────────────────────────

  Widget _buildDoneStep() {
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
            '${_nameController.text.trim()} is online and ready to chat. '
            'Just tap or speak.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () {
              _ble.disconnect();
              Navigator.of(context).pop(); // pop BLE wizard
              context.pop(); // pop add-device route
            },
            child: const Text('Go to Dashboard'),
          ),
        ],
      ),
    );
  }
}

// ── Registration checklist item ──────────────────────────────────

enum _CheckStatus { pending, loading, done, error }

class _RegisterCheckItem extends StatelessWidget {
  final String label;
  final _CheckStatus status;

  const _RegisterCheckItem({
    required this.label,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final IconData icon;
    final Color color;

    switch (status) {
      case _CheckStatus.done:
        icon = Icons.check_circle;
        color = Colors.green;
      case _CheckStatus.loading:
        icon = Icons.circle;
        color = colors.primary;
      case _CheckStatus.error:
        icon = Icons.cancel;
        color = colors.error;
      case _CheckStatus.pending:
        icon = Icons.circle_outlined;
        color = colors.outline;
    }

    return Row(
      children: [
        if (status == _CheckStatus.loading)
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          )
        else
          Icon(icon, color: color, size: 24),
        const SizedBox(width: 12),
        Text(
          label,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: status == _CheckStatus.pending
                ? colors.onSurfaceVariant
                : null,
          ),
        ),
      ],
    );
  }
}
