import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wifi_scan/wifi_scan.dart';

import 'package:go_router/go_router.dart';

import '../../../../core/ble/ble_constants.dart';
import '../../../../core/ble/ble_provisioning_service.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/local/local_device_store.dart';
import '../../../../core/widgets/step_progress_bar.dart';
import '../../../../core/widgets/success_screen.dart';

/// 3-step BLE provisioning wizard.
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
      duration: AppConstants.animNormal,
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
      _scanWifiNetworks();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: $e')),
      );
    }
  }

  // ── Step 2: Wi-Fi scan + select ──────────────────────────────

  List<WiFiAccessPoint> _wifiNetworks = [];
  bool _isScanningWifi = false;
  String _wifiSearchQuery = '';

  Future<void> _scanWifiNetworks() async {
    setState(() => _isScanningWifi = true);

    try {
      final can = await WiFiScan.instance.canStartScan();
      if (can == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
        await Future.delayed(const Duration(seconds: 2));
      }

      final results = await WiFiScan.instance.getScannedResults();
      final seen = <String>{};
      final unique = <WiFiAccessPoint>[];
      results.sort((a, b) => b.level.compareTo(a.level));
      for (final ap in results) {
        if (ap.ssid.isNotEmpty && seen.add(ap.ssid)) {
          unique.add(ap);
        }
      }

      if (mounted) {
        setState(() {
          _wifiNetworks = unique;
          _isScanningWifi = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isScanningWifi = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Wi-Fi scan failed: $e')),
        );
      }
    }
  }

  void _selectWifiNetwork(String ssid) {
    setState(() => _ssidController.text = ssid);
  }

  List<WiFiAccessPoint> get _filteredNetworks {
    if (_wifiSearchQuery.isEmpty) return _wifiNetworks;
    final q = _wifiSearchQuery.toLowerCase();
    return _wifiNetworks.where((ap) => ap.ssid.toLowerCase().contains(q)).toList();
  }

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
          await _onProvisioningSuccess(ssid);
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

      if (_wifiStatus == BleConstants.wifiConnecting) {
        if (!mounted) return;
        await _onProvisioningSuccess(ssid);
        return;
      }
    } catch (e) {
      if (!mounted) return;

      if (_wifiStatus == BleConstants.wifiConnecting) {
        await _onProvisioningSuccess(ssid);
        return;
      }

      setState(() {
        _isConnectingWifi = false;
        _wifiError = 'Error: $e';
      });
    }
  }

  Future<void> _onProvisioningSuccess(String ssid) async {
    final device = LocalDeviceStore.create(
      name: _connectedDeviceName,
      ssid: ssid,
    );
    await LocalDeviceStore.save(device);

    if (!mounted) return;
    setState(() => _isConnectingWifi = false);
    _goToStep(2);
  }

  Future<void> _showManualSsidDialog() async {
    final controller = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            AppConstants.spacingXxl,
            AppConstants.spacingSm,
            AppConstants.spacingXxl,
            MediaQuery.of(ctx).viewInsets.bottom + AppConstants.spacingXxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Enter Network Name',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: AppConstants.spacingLg),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Wi-Fi SSID',
                  prefixIcon: Icon(Icons.wifi),
                ),
              ),
              const SizedBox(height: AppConstants.spacingXxl),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Done'),
              ),
              const SizedBox(height: AppConstants.spacingSm),
            ],
          ),
        );
      },
    );
    if (result != null && result.isNotEmpty) {
      _selectWifiNetwork(result);
    }
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final stepLabels = ['Find device', 'Wi-Fi setup', 'Done'];

    return Scaffold(
      appBar: AppBar(
        title: Text(stepLabels[_step]),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          StepProgressBar(current: _step, total: 3),
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
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingLg,
        AppConstants.spacingSm,
        AppConstants.spacingLg,
        AppConstants.spacingLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppConstants.spacingMd),
          Text(
            'Find your Aksabot',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppConstants.spacingXs),
          Text(
            'Make sure your Aksabot is powered on, then tap Scan.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          AnimatedSwitcher(
            duration: AppConstants.animFast,
            child: _isScanning
                ? const LinearProgressIndicator(key: ValueKey('progress'))
                : const SizedBox(height: 4, key: ValueKey('spacer')),
          ),
          const SizedBox(height: AppConstants.spacingMd),

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
                        onConnect: () => _selectDevice(result.device, name),
                      );
                    },
                  ),
          ),

          const SizedBox(height: AppConstants.spacingMd),
          FilledButton.icon(
            onPressed: () {
              if (_isScanning) {
                FlutterBluePlus.stopScan();
              } else {
                _startScan();
              }
            },
            icon: Icon(_isScanning ? Icons.stop : Icons.search),
            label: Text(_isScanning ? 'Scanning...' : 'Scan for Devices'),
          ),
          const SizedBox(height: AppConstants.spacingXs),
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
    final selectedSsid = _ssidController.text.trim();

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spacingXxl,
            AppConstants.spacingSm,
            AppConstants.spacingXxl,
            0,
          ),
          child: Column(
            children: [
              Text('Select Wi-Fi Network', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppConstants.spacingXs),
              Text(
                'Choose the network for $_connectedDeviceName',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        // If a network is selected → password input
        if (selectedSsid.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingXxl,
              AppConstants.spacingMd,
              AppConstants.spacingXxl,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Selected network chip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacingMd,
                    vertical: AppConstants.spacingSm,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi, size: 18, color: colors.onPrimaryContainer),
                      const SizedBox(width: AppConstants.spacingSm),
                      Expanded(
                        child: Text(
                          selectedSsid,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, size: 18, color: colors.onPrimaryContainer),
                        onPressed: () => setState(() => _ssidController.clear()),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppConstants.spacingMd),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  autofocus: true,
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
                const SizedBox(height: AppConstants.spacingMd),

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

                const SizedBox(height: AppConstants.spacingSm),
                FilledButton(
                  onPressed: _isConnectingWifi ? null : _connectWifi,
                  child: Text(_isConnectingWifi ? 'Connecting...' : 'Connect'),
                ),
              ],
            ),
          ),
        ],

        // Network list (when no network selected)
        if (selectedSsid.isEmpty) ...[
          const SizedBox(height: AppConstants.spacingSm),
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingXxl),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search networks...',
                prefixIcon: Icon(Icons.search, size: AppConstants.iconMd),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) => setState(() => _wifiSearchQuery = v),
            ),
          ),
          const SizedBox(height: AppConstants.spacingXs),

          if (_isScanningWifi)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppConstants.spacingXs),
              child: LinearProgressIndicator(),
            )
          else
            const SizedBox(height: AppConstants.spacingXs),

          // Network list
          Expanded(
            child: _filteredNetworks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isScanningWifi ? Icons.wifi_find : Icons.wifi_off,
                          size: AppConstants.iconXxl,
                          color: colors.onSurfaceVariant.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: AppConstants.spacingMd),
                        Text(
                          _isScanningWifi
                              ? 'Scanning...'
                              : 'No networks found.\nTap Scan to search.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spacingLg,
                    ),
                    itemCount: _filteredNetworks.length,
                    itemBuilder: (context, index) {
                      final ap = _filteredNetworks[index];
                      return _WifiNetworkTile(
                        ssid: ap.ssid,
                        rssi: ap.level,
                        isSecure: ap.capabilities.contains('WPA') ||
                            ap.capabilities.contains('WEP'),
                        onTap: () => _selectWifiNetwork(ap.ssid),
                      );
                    },
                  ),
          ),

          // Bottom buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingXxl,
              AppConstants.spacingSm,
              AppConstants.spacingXxl,
              AppConstants.spacingLg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _isScanningWifi ? null : _scanWifiNetworks,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(_isScanningWifi ? 'Scanning...' : 'Scan Networks'),
                ),
                const SizedBox(height: AppConstants.spacingXs),
                TextButton(
                  onPressed: _showManualSsidDialog,
                  child: const Text('Enter network name manually'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Step 3: Done ─────────────────────────────────────────────

  Widget _buildDoneStep() {
    final ssid = _ssidController.text.trim();

    return SuccessScreen(
      title: '$_connectedDeviceName is connected!',
      subtitle: ssid.isNotEmpty
          ? 'Successfully joined "$ssid".\nYour Aksabot is online and ready.'
          : 'Your Aksabot is connected to the internet and ready.',
      hint: 'Connect to backend later to unlock AI features',
      onPressed: () {
        _ble.disconnect();
        context.go('/home');
      },
    );
  }
}

// ── Reusable widgets ─────────────────────────────────────────────

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
            isScanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
            size: AppConstants.iconHuge,
            color: colors.onSurfaceVariant.withValues(alpha: 0.35),
          ),
          const SizedBox(height: AppConstants.spacingLg),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingLg,
            vertical: AppConstants.spacingMd,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Icon(
                  Icons.smart_toy_outlined,
                  color: colors.onPrimaryContainer,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppConstants.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleSmall),
                    const SizedBox(height: AppConstants.spacingXxs),
                    Row(
                      children: [
                        Icon(_signalIcon(rssi),
                            size: 12, color: colors.onSurfaceVariant),
                        const SizedBox(width: AppConstants.spacingXs),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacingLg,
                    vertical: AppConstants.spacingSm,
                  ),
                ),
                child: const Text('Connect'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WifiNetworkTile extends StatelessWidget {
  final String ssid;
  final int rssi;
  final bool isSecure;
  final VoidCallback onTap;

  const _WifiNetworkTile({
    required this.ssid,
    required this.rssi,
    required this.isSecure,
    required this.onTap,
  });

  IconData _signalIcon(int rssi) {
    if (rssi >= -50) return Icons.signal_wifi_4_bar;
    if (rssi >= -65) return Icons.network_wifi_3_bar;
    if (rssi >= -75) return Icons.network_wifi_2_bar;
    return Icons.network_wifi_1_bar;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacingXs),
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          leading: Icon(_signalIcon(rssi), color: colors.primary, size: 22),
          title: Text(ssid, style: theme.textTheme.bodyMedium),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSecure)
                Icon(Icons.lock_outlined, size: 14, color: colors.onSurfaceVariant),
              const SizedBox(width: AppConstants.spacingXs),
              Text(
                '$rssi dBm',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          onTap: onTap,
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
      padding: const EdgeInsets.only(bottom: AppConstants.spacingXs),
      child: Row(
        children: [
          if (isLoading)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else if (icon != null)
            Icon(icon, size: AppConstants.iconSm, color: color),
          const SizedBox(width: AppConstants.spacingSm),
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
