import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../domain/entities/device_entity.dart';
import '../bloc/devices_bloc.dart';

class DeviceDetailPage extends StatelessWidget {
  final String deviceId;
  const DeviceDetailPage({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<DevicesBloc>()..add(LoadDevice(deviceId)),
      child: _DeviceDetailView(deviceId: deviceId),
    );
  }
}

class _DeviceDetailView extends StatelessWidget {
  final String deviceId;
  const _DeviceDetailView({required this.deviceId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return BlocConsumer<DevicesBloc, DevicesState>(
      listener: (context, state) {
        if (state is DevicesError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        final device =
            state is DeviceDetailLoaded ? state.device : null;

        return Scaffold(
          appBar: AppBar(
            title: Text(device?.name ?? 'Device'),
            actions: [
              if (device != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete device',
                  onPressed: () => _confirmDelete(context, device),
                ),
            ],
          ),
          body: state is DevicesLoading
              ? const Center(child: CircularProgressIndicator())
              : device == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline,
                              size: 48, color: colors.error),
                          const SizedBox(height: 16),
                          FilledButton.tonal(
                            onPressed: () => context
                                .read<DevicesBloc>()
                                .add(LoadDevice(deviceId)),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          TabBar(
                            tabs: const [
                              Tab(text: 'Settings'),
                              Tab(text: 'Personality'),
                            ],
                            labelColor: colors.primary,
                            unselectedLabelColor: colors.onSurfaceVariant,
                            indicatorColor: colors.primary,
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _SettingsTab(device: device),
                                _PersonalityTab(device: device),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
        );
      },
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
              context.read<DevicesBloc>().add(DeleteDevice(device.id));
              Navigator.of(dialogContext).pop();
              context.pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings tab
// ---------------------------------------------------------------------------

class _SettingsTab extends StatefulWidget {
  final Device device;
  const _SettingsTab({required this.device});

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  late final TextEditingController _nameController;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.device.name);
    _nameController.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant _SettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id) {
      _nameController.text = widget.device.name;
      _dirty = false;
    }
  }

  void _onChanged() {
    final isDirty = _nameController.text.trim() != widget.device.name;
    if (isDirty != _dirty) setState(() => _dirty = isDirty);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    context.read<DevicesBloc>().add(
          UpdateSettings(widget.device.id, {'name': name}),
        );
    setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final online = widget.device.isOnline;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: online ? Colors.green : colors.outline,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  online ? 'Online' : 'Offline',
                  style: theme.textTheme.titleSmall,
                ),
                const Spacer(),
                if (widget.device.lastSeenAt != null)
                  Text(
                    'Last seen: ${_formatDateTime(widget.device.lastSeenAt!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Name field
        Text('Device Name', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(hintText: 'Enter device name'),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 24),

        // Save button
        FilledButton(
          onPressed: _dirty ? _save : null,
          child: const Text('Save Settings'),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ---------------------------------------------------------------------------
// Personality tab
// ---------------------------------------------------------------------------

class _PersonalityTab extends StatefulWidget {
  final Device device;
  const _PersonalityTab({required this.device});

  @override
  State<_PersonalityTab> createState() => _PersonalityTabState();
}

class _PersonalityTabState extends State<_PersonalityTab> {
  late final TextEditingController _nameController;
  late final TextEditingController _toneController;
  late final TextEditingController _languageController;
  late final TextEditingController _systemPromptController;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final p = widget.device.personalityJson;
    _nameController = TextEditingController(text: p['name'] as String? ?? '');
    _toneController = TextEditingController(text: p['tone'] as String? ?? '');
    _languageController =
        TextEditingController(text: p['language'] as String? ?? '');
    _systemPromptController =
        TextEditingController(text: p['system_prompt'] as String? ?? '');

    for (final c in _controllers) {
      c.addListener(_onChanged);
    }
  }

  List<TextEditingController> get _controllers => [
        _nameController,
        _toneController,
        _languageController,
        _systemPromptController,
      ];

  @override
  void didUpdateWidget(covariant _PersonalityTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id) {
      _syncFromDevice();
    }
  }

  void _syncFromDevice() {
    final p = widget.device.personalityJson;
    _nameController.text = p['name'] as String? ?? '';
    _toneController.text = p['tone'] as String? ?? '';
    _languageController.text = p['language'] as String? ?? '';
    _systemPromptController.text = p['system_prompt'] as String? ?? '';
    _dirty = false;
  }

  void _onChanged() {
    final p = widget.device.personalityJson;
    final isDirty = _nameController.text.trim() != (p['name'] ?? '') ||
        _toneController.text.trim() != (p['tone'] ?? '') ||
        _languageController.text.trim() != (p['language'] ?? '') ||
        _systemPromptController.text.trim() != (p['system_prompt'] ?? '');
    if (isDirty != _dirty) setState(() => _dirty = isDirty);
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    context.read<DevicesBloc>().add(
          UpdatePersonality(widget.device.id, {
            'name': _nameController.text.trim(),
            'tone': _toneController.text.trim(),
            'language': _languageController.text.trim(),
            'system_prompt': _systemPromptController.text.trim(),
          }),
        );
    setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Personality Name', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(hintText: 'e.g. Aksa'),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 16),

        Text('Tone', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _toneController,
          decoration:
              const InputDecoration(hintText: 'e.g. friendly, sarcastic'),
        ),
        const SizedBox(height: 16),

        Text('Language', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _languageController,
          decoration: const InputDecoration(hintText: 'e.g. en, id'),
        ),
        const SizedBox(height: 16),

        Text('System Prompt', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _systemPromptController,
          decoration: const InputDecoration(
            hintText: 'Custom instructions for the AI...',
            alignLabelWithHint: true,
          ),
          maxLines: 5,
          minLines: 3,
        ),
        const SizedBox(height: 24),

        FilledButton(
          onPressed: _dirty ? _save : null,
          child: const Text('Save Personality'),
        ),
      ],
    );
  }
}
