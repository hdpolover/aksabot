import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../domain/repositories/devices_repository.dart';
import 'ble_provisioning_page.dart';

/// Add Device screen — choose between Wi-Fi (manual token) or Bluetooth.
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

          // Option 1: Wi-Fi (manual token entry)
          _ConnectionOption(
            icon: Icons.wifi,
            title: 'Wi-Fi (Manual)',
            description:
                'Enter a device token to connect. Use this when you '
                'already have the token from the device setup.',
            tag: 'Available now',
            tagColor: colors.primary,
            onTap: () => _showWifiFlow(context),
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
            onTap: () => _showBleFlow(context),
          ),
        ],
      ),
    );
  }

  void _showWifiFlow(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _WifiAddDevicePage()),
    );
  }

  void _showBleFlow(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BleProvisioningPage()),
    );
  }
}

// ---------------------------------------------------------------------------
// Wi-Fi flow: enter token → register device → name → done
// ---------------------------------------------------------------------------

class _WifiAddDevicePage extends StatefulWidget {
  const _WifiAddDevicePage();

  @override
  State<_WifiAddDevicePage> createState() => _WifiAddDevicePageState();
}

class _WifiAddDevicePageState extends State<_WifiAddDevicePage> {
  final _tokenController = TextEditingController();

  bool _isLoading = false;
  String? _error;
  String? _deviceName;
  bool _claimed = false;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _claimDevice() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Please enter a device token');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final repo = sl<DevicesRepository>();
    final result = await repo.claimByToken(token);

    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _isLoading = false;
      }),
      (device) => setState(() {
        _deviceName = device.name;
        _claimed = true;
        _isLoading = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Add via Wi-Fi')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _claimed ? _buildSuccess(theme, colors) : _buildForm(theme, colors),
      ),
    );
  }

  Widget _buildForm(ThemeData theme, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.vpn_key_outlined, size: 48, color: colors.primary),
        const SizedBox(height: 16),
        Text(
          'Enter Device Token',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Paste the device token from your ESP32 or run the '
          'simulator (npm run esp:sim) and copy the token from the terminal.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _tokenController,
          decoration: const InputDecoration(
            labelText: 'Device token',
            hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
            prefixIcon: Icon(Icons.key),
          ),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: colors.error)),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _isLoading ? null : _claimDevice,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Link Device'),
        ),
      ],
    );
  }

  Widget _buildSuccess(ThemeData theme, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Icon(Icons.check_circle, size: 64, color: Colors.green),
        const SizedBox(height: 16),
        Text(
          'Device found!',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '"${_deviceName ?? 'Unknown'}" has been linked to your account. '
          'If the device is connected, it will appear online on your dashboard.',
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
    );
  }
}

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
