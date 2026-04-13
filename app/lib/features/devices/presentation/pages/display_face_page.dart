import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../domain/entities/device_entity.dart';
import '../../domain/repositories/devices_repository.dart';

/// Display & Face settings — face style (ORBIT / NOVA) and idle display mode.
class DisplayFacePage extends StatefulWidget {
  final String deviceId;
  const DisplayFacePage({super.key, required this.deviceId});

  @override
  State<DisplayFacePage> createState() => _DisplayFacePageState();
}

class _DisplayFacePageState extends State<DisplayFacePage> {
  final _devicesRepo = sl<DevicesRepository>();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  Device? _device;

  String _faceStyle = 'nova';
  String _idleDisplayMode = 'face';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _devicesRepo.getDevice(widget.deviceId);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _error = failure.message;
        _loading = false;
      }),
      (device) {
        final s = device.settingsJson;
        final fs = s['face_style'] as String?;
        final idm = s['idle_display_mode'] as String?;
        setState(() {
          _device = device;
          _faceStyle = (fs == 'orbit' || fs == 'nova') ? fs! : 'nova';
          _idleDisplayMode =
              (idm == 'face' || idm == 'clock' || idm == 'status')
                  ? idm!
                  : 'face';
          _loading = false;
        });
      },
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final result = await _devicesRepo.updateSettings(widget.deviceId, {
      'face_style': _faceStyle,
      'idle_display_mode': _idleDisplayMode,
    });
    if (!mounted) return;

    result.fold(
      (failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: ${failure.message}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      },
      (device) {
        setState(() => _device = device);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved')),
        );
      },
    );

    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Display & Face')),
        body: const AppLoadingIndicator(),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Display & Face')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colors.error),
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: colors.error)),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _loadSettings,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Display & Face'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Face preview ──────────────────────────────────────────────
          _FacePreview(faceStyle: _faceStyle),
          const SizedBox(height: AppConstants.spacingXxl),

          // ── Face Style ────────────────────────────────────────────────
          Text('Face Style', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            'Changes how Aksa\'s eyes look on the display.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spacingLg),
              child: Column(
                children: [
                  _StyleOption(
                    value: 'nova',
                    groupValue: _faceStyle,
                    title: 'Nova',
                    subtitle: 'Flat rounded-rectangle eyes — modern, geometric',
                    onTap: () => setState(() => _faceStyle = 'nova'),
                    preview: _EyePreview.rounded(),
                  ),
                  const Divider(height: AppConstants.spacingXxl),
                  _StyleOption(
                    value: 'orbit',
                    groupValue: _faceStyle,
                    title: 'Orbit',
                    subtitle: 'Classic circle eyes with pupil — friendly, cartoon',
                    onTap: () => setState(() => _faceStyle = 'orbit'),
                    preview: _EyePreview.circle(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingXxl),

          // ── Idle Display Mode ─────────────────────────────────────────
          Text('Idle Display Mode', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            'What Aksa shows on screen when inactive.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final option in _idleModeOptions)
                  _IdleModeRow(
                    value: option.$1,
                    groupValue: _idleDisplayMode,
                    label: option.$2,
                    subtitle: option.$3,
                    icon: option.$4,
                    onTap: () => setState(() => _idleDisplayMode = option.$1),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacingXxl),

          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save Settings'),
          ),
          const SizedBox(height: AppConstants.spacingXxxl),
        ],
      ),
    );
  }
}

// ── Idle mode options ─────────────────────────────────────────────────────────

const _idleModeOptions = [
  ('face', 'Face', 'Animated face — the default', Icons.face_rounded),
  ('clock', 'Clock', 'Large time and date display', Icons.access_time_rounded),
  ('status', 'Status', 'Connection info and system stats', Icons.bar_chart_rounded),
];

// ── Face preview widget ───────────────────────────────────────────────────────

class _FacePreview extends StatelessWidget {
  final String faceStyle;
  const _FacePreview({required this.faceStyle});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isNova = faceStyle == 'nova';

    return Card(
      color: Colors.black,
      child: SizedBox(
        height: 140,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isNova) ...[
                    _RoundedEye(color: colors.primary),
                    const SizedBox(width: 28),
                    _RoundedEye(color: colors.primary),
                  ] else ...[
                    _CircleEye(color: colors.primary),
                    const SizedBox(width: 28),
                    _CircleEye(color: colors.primary),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: 40,
                height: 3,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundedEye extends StatelessWidget {
  final Color color;
  const _RoundedEye({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 19,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }
}

class _CircleEye extends StatelessWidget {
  final Color color;
  const _CircleEye({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Colors.black,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// ── Style option row ──────────────────────────────────────────────────────────

class _StyleOption extends StatelessWidget {
  final String value;
  final String groupValue;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget preview;

  const _StyleOption({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = value == groupValue;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              groupValue: groupValue,
              onChanged: (_) => onTap(),
            ),
            const SizedBox(width: AppConstants.spacingSm),
            preview,
            const SizedBox(width: AppConstants.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EyePreview extends StatelessWidget {
  final bool rounded;
  const _EyePreview.rounded() : rounded = true;
  const _EyePreview.circle() : rounded = false;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return Container(
      width: 52,
      height: 32,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (rounded) ...[
            Container(
              width: 14, height: 9,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 14, height: 9,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ] else ...[
            Container(
              width: 11, height: 11,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Container(
              width: 11, height: 11,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Idle mode row ─────────────────────────────────────────────────────────────

class _IdleModeRow extends StatelessWidget {
  final String value;
  final String groupValue;
  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _IdleModeRow({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RadioListTile<String>(
      value: value,
      groupValue: groupValue,
      onChanged: (_) => onTap(),
      secondary: Icon(icon, color: theme.colorScheme.primary),
      title: Text(label),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }
}
