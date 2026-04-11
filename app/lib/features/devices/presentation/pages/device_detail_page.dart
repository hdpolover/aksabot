import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../../../core/widgets/status_dot.dart';
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
              ? const AppLoadingIndicator()
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
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final bloc = context.read<DevicesBloc>();
              bloc.add(DeleteDevice(device.id));
              // Wait for the bloc to finish the delete before popping
              await bloc.stream.firstWhere(
                (s) => s is DevicesLoaded || s is DevicesError,
              );
              if (context.mounted) context.pop();
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
  double _volume = 80;
  double _brightness = 80;
  bool _showTranscript = true;
  String _idleTimeout = '30';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.device.name);
    _nameController.addListener(_onChanged);
    // Load settings from device JSON
    final s = widget.device.settingsJson;
    _volume = (s['volume'] as num?)?.toDouble() ?? 80;
    _brightness = (s['brightness'] as num?)?.toDouble() ?? 80;
    _showTranscript = s['showTranscript'] as bool? ?? true;
    _idleTimeout = (s['idleTimeoutMinutes'] ?? 30).toString();
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
          UpdateSettings(widget.device.id, {
            'name': name,
            'volume': _volume.round(),
            'brightness': _brightness.round(),
            'showTranscript': _showTranscript,
            'idleTimeoutMinutes': int.parse(_idleTimeout),
          }),
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
        // General section
        Text('General', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Device name
                Text('Device name', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  decoration:
                      const InputDecoration(hintText: 'Enter device name'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),

                // Volume
                Row(
                  children: [
                    Text('Volume', style: theme.textTheme.bodyMedium),
                    const Spacer(),
                    Text('${_volume.round()}%',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
                Slider(
                  value: _volume,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  onChanged: (v) => setState(() {
                    _volume = v;
                    _dirty = true;
                  }),
                ),

                // Brightness
                Row(
                  children: [
                    Text('Brightness', style: theme.textTheme.bodyMedium),
                    const Spacer(),
                    Text('${_brightness.round()}%',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
                Slider(
                  value: _brightness,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  onChanged: (v) => setState(() {
                    _brightness = v;
                    _dirty = true;
                  }),
                ),
                const SizedBox(height: 8),

                // Show transcript toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Show transcript', style: theme.textTheme.bodyMedium),
                    Switch(
                      value: _showTranscript,
                      onChanged: (v) => setState(() {
                        _showTranscript = v;
                        _dirty = true;
                      }),
                    ),
                  ],
                ),

                // Idle timeout
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Idle timeout', style: theme.textTheme.bodyMedium),
                    DropdownButton<String>(
                      value: _idleTimeout,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: '1', child: Text('1 min')),
                        DropdownMenuItem(value: '5', child: Text('5 min')),
                        DropdownMenuItem(value: '10', child: Text('10 min')),
                        DropdownMenuItem(value: '30', child: Text('30 min')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _idleTimeout = v;
                            _dirty = true;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Save button
        FilledButton(
          onPressed: _dirty ? _save : null,
          child: const Text('Save Settings'),
        ),
        const SizedBox(height: 24),

        // Device info
        Text('Device Info', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                title: const Text('Status'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusDot(
                      variant: online
                          ? StatusDotVariant.online
                          : StatusDotVariant.offline,
                    ),
                    const SizedBox(width: AppConstants.spacingSm),
                    Text(
                      online ? 'Online' : 'Offline',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Wi-Fi signal'),
                trailing: Text(
                  'Requires BLE',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Uptime'),
                trailing: Text(
                  online && widget.device.lastSeenAt != null
                      ? _formatUptime(
                          DateTime.now().difference(widget.device.lastSeenAt!))
                      : 'Offline',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Firmware'),
                trailing: Text(
                  'Requires BLE',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Remove device
        OutlinedButton.icon(
          onPressed: () => _confirmDelete(context),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Remove Device'),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.error,
            side: BorderSide(color: colors.error),
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      ],
    );
  }

  String _formatUptime(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Device'),
        content: Text('Remove "${widget.device.name}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final bloc = context.read<DevicesBloc>();
              bloc.add(DeleteDevice(widget.device.id));
              await bloc.stream.firstWhere(
                (s) => s is DevicesLoaded || s is DevicesError,
              );
              if (context.mounted) context.pop();
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
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
  late final TextEditingController _customToneController;
  late final TextEditingController _systemPromptController;
  bool _dirty = false;
  String _selectedTone = 'friendly';
  String _selectedLanguage = 'en';
  bool _advancedExpanded = false;

  static const _tonePresets = [
    'professional',
    'friendly',
    'playful',
    'sarcastic',
    'custom',
  ];

  static const _languages = {
    'en': 'English',
    'id': 'Bahasa Indonesia',
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'ja': 'Japanese',
    'ko': 'Korean',
    'zh': 'Chinese',
  };

  @override
  void initState() {
    super.initState();
    final p = widget.device.personalityJson;
    _nameController = TextEditingController(text: p['name'] as String? ?? '');
    _systemPromptController =
        TextEditingController(text: p['system_prompt'] as String? ?? '');
    _customToneController = TextEditingController();

    // Resolve tone — check if it matches a preset
    final savedTone = p['tone'] as String? ?? 'friendly';
    if (_tonePresets.contains(savedTone)) {
      _selectedTone = savedTone;
    } else {
      _selectedTone = 'custom';
      _customToneController.text = savedTone;
    }

    // Resolve language
    final savedLang = p['language'] as String? ?? 'en';
    _selectedLanguage = _languages.containsKey(savedLang) ? savedLang : 'en';

    _nameController.addListener(_markDirty);
    _customToneController.addListener(_markDirty);
    _systemPromptController.addListener(_markDirty);
  }

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
    _systemPromptController.text = p['system_prompt'] as String? ?? '';
    final savedTone = p['tone'] as String? ?? 'friendly';
    if (_tonePresets.contains(savedTone)) {
      _selectedTone = savedTone;
      _customToneController.text = '';
    } else {
      _selectedTone = 'custom';
      _customToneController.text = savedTone;
    }
    final savedLang = p['language'] as String? ?? 'en';
    _selectedLanguage = _languages.containsKey(savedLang) ? savedLang : 'en';
    _dirty = false;
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _customToneController.dispose();
    _systemPromptController.dispose();
    super.dispose();
  }

  String get _effectiveTone => _selectedTone == 'custom'
      ? _customToneController.text.trim()
      : _selectedTone;

  void _save() {
    context.read<DevicesBloc>().add(
          UpdatePersonality(widget.device.id, {
            'name': _nameController.text.trim(),
            'tone': _effectiveTone,
            'language': _selectedLanguage,
            'system_prompt': _systemPromptController.text.trim(),
          }),
        );
    setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Bot name
        Text('Bot name', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(hintText: 'e.g. Aksa'),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 20),

        // Tone presets
        Text('Tone', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: RadioGroup<String>(
            groupValue: _selectedTone,
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  _selectedTone = v;
                  _dirty = true;
                });
              }
            },
            child: Column(
              children: [
                for (final tone in _tonePresets)
                  ListTile(
                    leading: Radio<String>(value: tone),
                    title: Text(
                      tone == 'custom'
                          ? 'Custom...'
                          : tone[0].toUpperCase() + tone.substring(1),
                    ),
                    onTap: () => setState(() {
                      _selectedTone = tone;
                      _dirty = true;
                    }),
                  ),
              ],
            ),
          ),
        ),
        if (_selectedTone == 'custom') ...[
          const SizedBox(height: 8),
          TextField(
            controller: _customToneController,
            decoration: const InputDecoration(
              hintText: 'Describe the tone...',
            ),
          ),
        ],
        const SizedBox(height: 20),

        // Language dropdown
        Text('Language', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedLanguage,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          items: _languages.entries
              .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _selectedLanguage = v;
                _dirty = true;
              });
            }
          },
        ),
        const SizedBox(height: 20),

        // Advanced — system prompt (expandable)
        Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: Icon(Icons.code, color: colors.onSurfaceVariant),
            title: const Text('Advanced'),
            initiallyExpanded: _advancedExpanded,
            onExpansionChanged: (v) => _advancedExpanded = v,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('System prompt (optional)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        )),
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
                  ],
                ),
              ),
            ],
          ),
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
