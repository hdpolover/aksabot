import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../devices/domain/entities/device_entity.dart';
import '../../../devices/presentation/bloc/devices_bloc.dart';
import '../../../devices/presentation/pages/device_detail_page.dart';

/// Home tab root.
///
/// - Loading: shows a loading indicator.
/// - One device registered: shows the device dashboard inline (no extra tap).
/// - Multiple devices: shows the dashboard for the selected device with a
///   dropdown in the AppBar to switch between them.
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

class _HomeViewState extends State<_HomeView> with WidgetsBindingObserver {
  List<Device> _devices = [];
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Refresh device list when the app comes back to the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<DevicesBloc>().add(const LoadDevices());
    }
  }

  Device? get _selectedDevice {
    if (_devices.isEmpty) return null;
    return _devices.where((d) => d.id == _selectedId).firstOrNull ??
        _devices.first;
  }

  void _selectDevice(String id) => setState(() => _selectedId = id);

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
        if (state is DevicesLoaded) {
          _devices = state.devices;
          // Keep the selected device valid; fall back to first on first load.
          if (_selectedId == null ||
              !_devices.any((d) => d.id == _selectedId)) {
            _selectedId = _devices.isNotEmpty ? _devices.first.id : null;
          }
        } else if (state is DeviceDetailLoaded) {
          // Pull-to-refresh inside the dashboard resolves here — sync list entry.
          final idx = _devices.indexWhere((d) => d.id == state.device.id);
          if (idx != -1) {
            _devices = List.of(_devices)..[idx] = state.device;
          }
        }

        if (state is DevicesLoading && _devices.isEmpty) {
          return const Scaffold(body: AppLoadingIndicator());
        }

        final device = _selectedDevice;
        if (device != null) {
          return _DeviceHome(
            devices: _devices,
            device: device,
            onDeviceChanged: _selectDevice,
          );
        }

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
  final List<Device> devices;
  final Device device;
  final ValueChanged<String> onDeviceChanged;

  const _DeviceHome({
    required this.devices,
    required this.device,
    required this.onDeviceChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: devices.length > 1
            ? _DeviceDropdown(
                devices: devices,
                selected: device,
                onChanged: onDeviceChanged,
              )
            : Text(device.name),
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

  Future<void> _confirmDelete(BuildContext context, Device device) async {
    final confirmed = await AppDialog.confirm(
      context,
      title: 'Delete Device',
      body: 'Remove "${device.name}" permanently?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed == true && context.mounted) {
      context.read<DevicesBloc>().add(DeleteDevice(device.id));
    }
  }
}

// ---------------------------------------------------------------------------
// Device dropdown — shown in AppBar when 2+ devices are registered
// ---------------------------------------------------------------------------

class _DeviceDropdown extends StatelessWidget {
  final List<Device> devices;
  final Device selected;
  final ValueChanged<String> onChanged;

  const _DeviceDropdown({
    required this.devices,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: selected.id,
        icon: Icon(Icons.expand_more_rounded, color: cs.onSurface, size: 20),
        isDense: true,
        style: tt.titleLarge?.copyWith(color: cs.onSurface),
        borderRadius: BorderRadius.circular(12),
        items: devices.map((d) {
          final online = d.isOnline;
          return DropdownMenuItem<String>(
            value: d.id,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: online ? Colors.green : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Text(d.name),
              ],
            ),
          );
        }).toList(),
        onChanged: (id) {
          if (id != null) onChanged(id);
        },
      ),
    );
  }
}
