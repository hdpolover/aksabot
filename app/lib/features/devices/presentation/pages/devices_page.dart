import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../../../core/widgets/device_tile.dart';
import '../../../../core/widgets/empty_state.dart';
import '../bloc/devices_bloc.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<DevicesBloc>()..add(const LoadDevices()),
      child: const _DevicesView(),
    );
  }
}

class _DevicesView extends StatelessWidget {
  const _DevicesView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context),
        child: const Icon(Icons.add),
      ),
      body: BlocBuilder<DevicesBloc, DevicesState>(
        builder: (context, state) {
          if (state is DevicesLoading) {
            return const AppLoadingIndicator();
          }

          if (state is DevicesError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colors.error),
                  const SizedBox(height: 16),
                  Text(state.message, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: () =>
                        context.read<DevicesBloc>().add(const LoadDevices()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (state is DevicesLoaded) {
            if (state.devices.isEmpty) {
              return const EmptyState(
                icon: Icons.devices_other,
                title: 'No devices yet',
                subtitle: 'Tap + to register a new device',
              );
            }

            return RefreshIndicator(
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
                itemCount: state.devices.length,
                itemBuilder: (context, index) {
                  final device = state.devices[index];
                  return DeviceTile(
                    name: device.name,
                    subtitle: device.isOnline
                        ? 'Online'
                        : _lastSeenLabel(device.lastSeenAt),
                    isOnline: device.isOnline,
                    onTap: () => context.push('/devices/${device.id}'),
                  );
                },
              ),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final controller = TextEditingController();
    showModalBottomSheet(
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
              Text('Register Device',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: AppConstants.spacingLg),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Device name (optional)',
                  hintText: 'e.g. Desk Buddy',
                ),
                autofocus: true,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: AppConstants.spacingXxl),
              FilledButton(
                onPressed: () {
                  final name = controller.text.trim().isEmpty
                      ? null
                      : controller.text.trim();
                  context.read<DevicesBloc>().add(CreateDevice(name: name));
                  Navigator.of(ctx).pop();
                },
                child: const Text('Create'),
              ),
              const SizedBox(height: AppConstants.spacingSm),
            ],
          ),
        );
      },
    );
  }
}

String _lastSeenLabel(DateTime? lastSeenAt) {
  if (lastSeenAt == null) return 'Never connected';
  final diff = DateTime.now().difference(lastSeenAt);
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
