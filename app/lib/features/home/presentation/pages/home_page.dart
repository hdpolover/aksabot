import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../devices/domain/entities/device_entity.dart';
import '../../../devices/presentation/bloc/devices_bloc.dart';
import '../../../devices/presentation/pages/device_detail_page.dart';

/// Home tab root.
///
/// - Loading: shows a loading indicator.
/// - One device registered: shows the device dashboard inline (no extra tap).
/// - No device: shows an "Add Aksa" empty state.
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
  // Cached so the UI doesn't flash to empty while refreshing or during
  // a LoadDevice call triggered by DeviceDashboardBody's pull-to-refresh.
  Device? _device;

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Poll every 30 s so online/offline status stays fresh without manual refresh.
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        context.read<DevicesBloc>().add(const LoadDevices());
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DevicesBloc, DevicesState>(
      listener: (context, state) {
        if (state is DevicesError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        // Update the device cache from any state that carries device data.
        if (state is DevicesLoaded) {
          _device = state.devices.isNotEmpty ? state.devices.first : null;
        } else if (state is DeviceDetailLoaded) {
          // DeviceDashboardBody's pull-to-refresh calls LoadDevice, which
          // resolves to DeviceDetailLoaded — keep the cache in sync.
          _device = state.device;
        }

        // First load with no cached data — show a spinner.
        if (state is DevicesLoading && _device == null) {
          return const Scaffold(body: AppLoadingIndicator());
        }

        // Device present — show its dashboard directly in this tab.
        if (_device != null) {
          return _DeviceHome(device: _device!);
        }

        // No device registered yet.
        return Scaffold(
          body: EmptyState(
            icon: Icons.smart_toy_rounded,
            title: 'No Aksa yet',
            subtitle: 'Pair your Aksabot to get started',
            actionLabel: 'Add Aksa',
            onAction: () => context.push('/devices/add').then((_) {
              if (context.mounted) {
                context.read<DevicesBloc>().add(const LoadDevices());
              }
            }),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Device home — AppBar + dashboard body embedded in the home tab
// ---------------------------------------------------------------------------

class _DeviceHome extends StatelessWidget {
  final Device device;
  const _DeviceHome({required this.device});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(device.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () =>
                context.read<DevicesBloc>().add(const LoadDevices()),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete device',
            onPressed: () => _confirmDelete(context, device),
          ),
        ],
      ),
      body: DeviceDashboardBody(device: device),
    );
  }

  void _confirmDelete(BuildContext context, Device device) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Device'),
        content: Text('Remove "${device.name}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.read<DevicesBloc>().add(DeleteDevice(device.id));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
