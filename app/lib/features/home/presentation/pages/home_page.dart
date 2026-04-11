import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/local/local_device.dart';
import '../../../../core/local/local_device_store.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../../../core/widgets/device_tile.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../devices/domain/entities/device_entity.dart';
import '../../../devices/presentation/bloc/devices_bloc.dart';

/// Home tab root. Shows a device grid when devices exist,
/// or an empty state when there are none.
///
/// Falls back to locally-provisioned devices when the backend is unavailable.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<DevicesBloc>()..add(const LoadDevices()),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView();

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  List<LocalDevice>? _localDevices;

  @override
  void initState() {
    super.initState();
    _loadLocalDevices();
  }

  Future<void> _loadLocalDevices() async {
    final devices = await LocalDeviceStore.getAll();
    if (mounted) setState(() => _localDevices = devices);
  }

  void _pushAndReload(BuildContext context, String path) {
    final bloc = context.read<DevicesBloc>();
    context.push(path).then((_) {
      if (mounted) {
        bloc.add(const LoadDevices());
        _loadLocalDevices();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DevicesBloc, DevicesState>(
      builder: (context, state) {
        // While waiting for the bloc AND local devices, show spinner
        if (state is DevicesLoading && _localDevices == null) {
          return const Scaffold(body: AppLoadingIndicator());
        }

        // Backend has devices — always show grid
        if (state is DevicesLoaded && state.devices.isNotEmpty) {
          return _DeviceList(
            devices: state.devices,
            onNavigate: _pushAndReload,
          );
        }

        // Backend unavailable or empty — show local devices if any
        final locals = _localDevices ?? [];

        if (locals.isNotEmpty) {
          return _LocalDeviceList(
            devices: locals,
            onAdd: () => _pushAndReload(context, '/devices/add'),
            onRemove: (id) async {
              await LocalDeviceStore.remove(id);
              _loadLocalDevices();
            },
          );
        }

        // Truly empty — no backend, no local devices
        return _EmptyState(onNavigate: _pushAndReload);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final void Function(BuildContext, String) onNavigate;
  const _EmptyState({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: EmptyState(
        icon: Icons.smart_toy_rounded,
        title: 'No devices yet',
        subtitle: 'Pair your Aksabot to get started',
        actionLabel: 'Add Device',
        onAction: () => onNavigate(context, '/devices/add'),
      ),
    );
  }
}


// ---------------------------------------------------------------------------
// Local device list (multiple, no backend)
// ---------------------------------------------------------------------------

class _LocalDeviceList extends StatelessWidget {
  final List<LocalDevice> devices;
  final VoidCallback onAdd;
  final void Function(String id) onRemove;

  const _LocalDeviceList({
    required this.devices,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      floatingActionButton: FloatingActionButton(
        onPressed: onAdd,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppConstants.spacingLg),
        children: [
          const _CloudSyncBanner(),
          const SizedBox(height: AppConstants.spacingLg),
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: AppConstants.spacingMd,
            crossAxisSpacing: AppConstants.spacingMd,
            childAspectRatio: 1.3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: devices
                .map((device) => LocalDeviceTile(
                      name: device.name,
                      ssid: device.ssid,
                      hasIp: device.localIp != null,
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Backend device list (backend online)
// ---------------------------------------------------------------------------

class _DeviceList extends StatelessWidget {
  final List<Device> devices;
  final void Function(BuildContext, String) onNavigate;
  const _DeviceList({required this.devices, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => onNavigate(context, '/devices/add'),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          context.read<DevicesBloc>().add(const LoadDevices());
        },
        child: GridView.builder(
          padding: const EdgeInsets.all(AppConstants.spacingLg),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: AppConstants.spacingMd,
            crossAxisSpacing: AppConstants.spacingMd,
            childAspectRatio: 1.3,
          ),
          itemCount: devices.length,
          itemBuilder: (context, index) {
            final device = devices[index];
            return DeviceTile(
              name: device.name,
              subtitle: device.isOnline ? 'Online' : 'Offline',
              isOnline: device.isOnline,
              onTap: () => onNavigate(context, '/devices/${device.id}'),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _CloudSyncBanner extends StatelessWidget {
  /// If provided, shows a "Connect" action button.
  /// Pass null when the device IP is not yet known.
  final VoidCallback? onConnect;

  const _CloudSyncBanner({this.onConnect});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final hasAction = onConnect != null;

    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, hasAction ? 4 : 14, 10),
      decoration: BoxDecoration(
        color: hasAction
            ? colors.primaryContainer.withValues(alpha: 0.55)
            : colors.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            hasAction ? Icons.cloud_queue : Icons.cloud_off,
            size: 18,
            color: hasAction
                ? colors.onPrimaryContainer
                : colors.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasAction
                  ? 'Connect to AI cloud to unlock voice features.'
                  : 'Not synced — find device on network to connect to AI cloud.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: hasAction
                    ? colors.onPrimaryContainer
                    : colors.onSecondaryContainer,
              ),
            ),
          ),
          if (hasAction) ...[
            TextButton(
              onPressed: onConnect,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('Connect'),
            ),
          ],
        ],
      ),
    );
  }
}

