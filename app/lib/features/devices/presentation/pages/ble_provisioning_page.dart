import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../../../core/ble/ble_constants.dart';
import '../../../../core/ble/ble_provisioning_service.dart';

/// 3-step BLE provisioning wizard.
///
/// Step 1: Scan for nearby Aksabot devices
/// Step 2: Enter home Wi-Fi credentials → sent to device via BLE
/// Step 3: Done — device is connected to the internet
///
/// No backend registration is required. Success = ESP32 reports wifiConnected.
class BleProvisioningPage extends StatefulWidget {
  const BleProvisioningPage({super.key});

  @override
  State<BleProvisioningPage> createState() => _BleProvisioningPageState();
}

class _BleProvisioningPageState extends State<BleProvisioningPage> {
  final _pageController = PageController();
  final _ble = BleProvisioningService();

  int _step = 0;
  String _connectedDeviceName = 'Aksabot';

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
  String? _wifiError;

  @override
  void dispose() {
    _scanSub?.cancel();
    _ble.disconnect();
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

  // ── Step 1: Scan ─────────────────────────────────────────────

  Future<void> _startScan() async {
    final btState = await FlutterBluePlus.adapterState.first;
    if (btState != BluetoothAdapterState.on) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable Bluetooth and try again.')),
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _scanResults = [];
    });

    try {
      _scanSub?.cancel();
      final resultsStream = await _ble.startScan();
      _scanSub = resultsStream.listen((results) {
        if (mounted) setState(() => _scanResults = results);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan failed: $e')),
      );
      return;
    }

    // Auto-stop after timeout
    await Future.delayed(const Duration(seconds: 10));
    if (mounted) {
      await _ble.stopScan();
      setState(() => _isScanning = false);
    }
  }

  Future<void> _selectDevice(BluetoothDevice device, String name) async {
    await _ble.stopScan();
    _scanSub?.cancel();
    setState(() {
      _isScanning = false;
      _connectedDeviceName = name.isNotEmpty ? name : 'Aksabot';
    });

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

    if (ssid.isEmpty) {
      setState(() => _wifiError = 'Please enter your Wi-Fi network name');
      return;
    }

    setState(() {
      _isConnectingWifi = true;
      _wifiStatus = BleConstants.wifiConnecting;
      _wifiError = null;
    });

    try {
      final statusStream = await _ble.writeWifiCredentials(ssid, password);

      await for (final status in statusStream) {
        if (!mounted) return;
        setState(() => _wifiStatus = status);

        if (status == BleConstants.wifiConnected) {
          setState(() => _isConnectingWifi = false);
          _goToStep(2); // Done
          return;
        }
        if (status == BleConstants.wifiFailed) {
          setState(() {
            _isConnectingWifi = false;
            _wifiError =
                'Wi-Fi connection failed. Check your credentials and try again.';
          });
          return;
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnectingWifi = false;
        _wifiError = 'Error: $e';
      });
    }
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final stepLabels = ['Find device', 'Wi-Fi setup', 'Done'];

    return Scaffold(
      appBar: AppBar(
        title: Text('Connect via Bluetooth — ${stepLabels[_step]}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Step progress bar
          _StepProgressBar(current: _step, total: 3),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildScanStep(),
                _buildWifiStep(),
                _buildDoneStep(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 1: Scan ─────────────────────────────────────────────

  Widget _buildScanStep() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Text(
            'Find your Aksabot',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Make sure your Aksabot is powered on, then tap Scan.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _isScanning
                ? const LinearProgressIndicator(key: ValueKey('progress'))
                : const SizedBox(height: 4, key: ValueKey('spacer')),
          ),
          const SizedBox(height: 12),

          // Results list
          Expanded(
            child: _scanResults.isEmpty
                ? _ScanEmptyState(isScanning: _isScanning)
                : ListView.builder(
                    itemCount: _scanResults.length,
                    itemBuilder: (context, index) {
                      final result = _scanResults[index];
                      final name =
                          result.advertisementData.advName.isNotEmpty
                              ? result.advertisementData.advName
                              : 'Aksabot';
                      return _DeviceTile(
                        name: name,
                        rssi: result.rssi,
                        onConnect: () =>
                            _selectDevice(result.device, name),
                      );
                    },
                  ),
          ),

          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isScanning ? null : _startScan,
            icon: Icon(_isScanning ? Icons.stop : Icons.search),
            label: Text(_isScanning ? 'Scanning...' : 'Scan for Devices'),
          ),
          const SizedBox(height: 6),
          Text(
            "Can't find it? Make sure Aksabot is powered on and nearby.",
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
            'Connect $_connectedDeviceName to Wi-Fi',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your home Wi-Fi credentials.\n'
            '$_connectedDeviceName will use these to connect to the internet.',
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
          const SizedBox(height: 20),

          // Live status feedback
          if (_wifiStatus == BleConstants.wifiConnecting)
            _InlineStatus(
              isLoading: true,
              label: 'Sending credentials to $_connectedDeviceName...',
              color: colors.primary,
            )
          else if (_wifiError != null)
            _InlineStatus(
              icon: Icons.error_outline,
              label: _wifiError!,
              color: colors.error,
            ),

          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isConnectingWifi ? null : _connectWifi,
            child: Text(_isConnectingWifi ? 'Connecting...' : 'Connect'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isConnectingWifi
                ? null
                : () {
                    _ble.disconnect();
                    _goToStep(0);
                  },
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }

  // ── Step 3: Done ─────────────────────────────────────────────

  Widget _buildDoneStep() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ssid = _ssidController.text.trim();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle_rounded, size: 72, color: Colors.green),
          const SizedBox(height: 20),
          Text(
            '$_connectedDeviceName is connected!',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            ssid.isNotEmpty
                ? 'Successfully joined "$ssid".\nYour Aksabot is online and ready.'
                : 'Your Aksabot is connected to the internet and ready.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          // Info chip
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    'To use AI features, connect to your backend later',
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
            onPressed: () {
              _ble.disconnect();
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

// ── Reusable widgets ─────────────────────────────────────────────

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

class _ScanEmptyState extends StatelessWidget {
  final bool isScanning;

  const _ScanEmptyState({required this.isScanning});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isScanning
                ? Icons.bluetooth_searching
                : Icons.bluetooth_disabled,
            size: 64,
            color: colors.onSurfaceVariant.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 16),
          Text(
            isScanning
                ? 'Searching for Aksabot...'
                : 'No devices found.\nTap Scan to search again.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final String name;
  final int rssi;
  final VoidCallback onConnect;

  const _DeviceTile({
    required this.name,
    required this.rssi,
    required this.onConnect,
  });

  String _signalLabel(int rssi) {
    if (rssi >= -60) return 'Strong';
    if (rssi >= -75) return 'Good';
    if (rssi >= -85) return 'Weak';
    return 'Very weak';
  }

  IconData _signalIcon(int rssi) {
    if (rssi >= -60) return Icons.signal_wifi_4_bar;
    if (rssi >= -75) return Icons.network_wifi_3_bar;
    return Icons.network_wifi_1_bar;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.smart_toy_outlined,
                color: colors.onPrimaryContainer,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(_signalIcon(rssi),
                          size: 12, color: colors.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        '${_signalLabel(rssi)}  ·  $rssi dBm',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: onConnect,
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineStatus extends StatelessWidget {
  final IconData? icon;
  final bool isLoading;
  final String label;
  final Color color;

  const _InlineStatus({
    this.icon,
    this.isLoading = false,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          if (isLoading)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else if (icon != null)
            Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
