import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_loading_indicator.dart';
import '../../domain/entities/device_entity.dart';
import '../../domain/repositories/devices_repository.dart';

/// Display & Behavior — face style, face colors, idle display mode, idle
/// chat/animations, and motion settings.
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
  bool _dirty = false;
  String? _error;

  // ── Display settings ──────────────────────────────────────────────────────
  String _faceStyle = 'nova';
  String _idleDisplayMode = 'face';

  // ── Face colors ───────────────────────────────────────────────────────────
  Color _bgColor    = const Color(0xFF000000);
  Color _eyeColor   = const Color(0xFFDADCE6);
  Color _mouthColor = const Color(0xFFFFFFFF);

  // ── Idle behavior settings ────────────────────────────────────────────────
  bool _idleChatEnabled = true;
  String _idleChatFrequency = 'normal';
  String _idleAnimationSpeed = 'normal';

  // Server copies for dirty detection
  String _serverFaceStyle = 'nova';
  String _serverIdleDisplayMode = 'face';
  Color _serverBgColor    = const Color(0xFF000000);
  Color _serverEyeColor   = const Color(0xFFDADCE6);
  Color _serverMouthColor = const Color(0xFFFFFFFF);
  bool _serverChatEnabled = true;
  String _serverChatFrequency = 'normal';
  String _serverAnimationSpeed = 'normal';

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
      _applyFromServer,
    );
  }

  void _applyFromServer(Device device) {
    final s = device.settingsJson;

    final fs = s['face_style'] as String?;
    final idm = s['idle_display_mode'] as String?;
    final bgHex    = s['face_bg_color']    as String?;
    final eyeHex   = s['face_eye_color']   as String?;
    final mouthHex = s['face_mouth_color'] as String?;
    final chatEnabled = s['idle_chat_enabled'] as bool? ?? true;
    final chatFreq = s['idle_chat_frequency'] as String? ?? 'normal';
    final animSpeed = s['idle_animation_speed'] as String? ?? 'normal';

    final faceStyle = (fs == 'orbit' || fs == 'nova') ? fs! : 'nova';
    final idleMode =
        (idm == 'face' || idm == 'clock' || idm == 'status') ? idm! : 'face';
    final bgColor    = _hexToColor(bgHex)    ?? const Color(0xFF000000);
    final eyeColor   = _hexToColor(eyeHex)   ?? const Color(0xFFDADCE6);
    final mouthColor = _hexToColor(mouthHex) ?? const Color(0xFFFFFFFF);

    setState(() {
      _faceStyle = faceStyle;
      _idleDisplayMode = idleMode;
      _bgColor    = bgColor;
      _eyeColor   = eyeColor;
      _mouthColor = mouthColor;
      _idleChatEnabled = chatEnabled;
      _idleChatFrequency = chatFreq;
      _idleAnimationSpeed = animSpeed;

      _serverFaceStyle = faceStyle;
      _serverIdleDisplayMode = idleMode;
      _serverBgColor    = bgColor;
      _serverEyeColor   = eyeColor;
      _serverMouthColor = mouthColor;
      _serverChatEnabled = chatEnabled;
      _serverChatFrequency = chatFreq;
      _serverAnimationSpeed = animSpeed;

      _dirty = false;
      _loading = false;
    });
  }

  void _markDirty() {
    final isDirty = _faceStyle != _serverFaceStyle ||
        _idleDisplayMode != _serverIdleDisplayMode ||
        _bgColor != _serverBgColor ||
        _eyeColor != _serverEyeColor ||
        _mouthColor != _serverMouthColor ||
        _idleChatEnabled != _serverChatEnabled ||
        _idleChatFrequency != _serverChatFrequency ||
        _idleAnimationSpeed != _serverAnimationSpeed;
    if (isDirty != _dirty) setState(() => _dirty = isDirty);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final patch = <String, dynamic>{};
    if (_faceStyle != _serverFaceStyle) patch['face_style'] = _faceStyle;
    if (_idleDisplayMode != _serverIdleDisplayMode) {
      patch['idle_display_mode'] = _idleDisplayMode;
    }
    if (_bgColor != _serverBgColor) {
      patch['face_bg_color'] = _colorToHex(_bgColor);
    }
    if (_eyeColor != _serverEyeColor) {
      patch['face_eye_color'] = _colorToHex(_eyeColor);
    }
    if (_mouthColor != _serverMouthColor) {
      patch['face_mouth_color'] = _colorToHex(_mouthColor);
    }
    if (_idleChatEnabled != _serverChatEnabled) {
      patch['idle_chat_enabled'] = _idleChatEnabled;
    }
    if (_idleChatFrequency != _serverChatFrequency) {
      patch['idle_chat_frequency'] = _idleChatFrequency;
    }
    if (_idleAnimationSpeed != _serverAnimationSpeed) {
      patch['idle_animation_speed'] = _idleAnimationSpeed;
    }

    if (patch.isEmpty) {
      setState(() => _saving = false);
      return;
    }

    final result = await _devicesRepo.updateSettings(widget.deviceId, patch);
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
        _applyFromServer(device);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved')),
        );
      },
    );

    if (mounted) setState(() => _saving = false);
  }

  // ── Color helpers ─────────────────────────────────────────────────────────

  /// Encodes a Color to a 6-char lowercase hex string (no leading #).
  static String _colorToHex(Color c) {
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    return '${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }

  /// Parses a 6-char hex string to a Color. Returns null for invalid input.
  static Color? _hexToColor(String? hex) {
    if (hex == null || hex.length < 6) return null;
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | (value & 0xFFFFFF));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Display & Behavior')),
        body: const AppLoadingIndicator(),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Display & Behavior')),
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
      appBar: AppBar(title: const Text('Display & Behavior')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              children: [
                // ── Live preview ──────────────────────────────────────
                _FacePreview(
                  faceStyle: _faceStyle,
                  bgColor: _bgColor,
                  eyeColor: _eyeColor,
                  mouthColor: _mouthColor,
                ),
                const SizedBox(height: AppConstants.spacingXxl),

                // ── Face Style ────────────────────────────────────────
                Text('Face Style', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppConstants.spacingXxs),
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
                          subtitle:
                              'Flat rounded-rectangle eyes — modern, geometric',
                          onTap: () {
                            setState(() => _faceStyle = 'nova');
                            _markDirty();
                          },
                          preview: _EyePreview.rounded(color: _eyeColor),
                        ),
                        const Divider(height: AppConstants.spacingXxl),
                        _StyleOption(
                          value: 'orbit',
                          groupValue: _faceStyle,
                          title: 'Orbit',
                          subtitle:
                              'Classic circle eyes with pupil — friendly, cartoon',
                          onTap: () {
                            setState(() => _faceStyle = 'orbit');
                            _markDirty();
                          },
                          preview: _EyePreview.circle(color: _eyeColor),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spacingXxl),

                // ── Face Colors ───────────────────────────────────────
                Text('Face Colors', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppConstants.spacingXxs),
                Text(
                  'Background and eye color — expression-specific colors '
                  'stay intact to keep Aksa emotionally expressive.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: AppConstants.spacingMd),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spacingLg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ColorSwatchRow(
                          label: 'Background',
                          selected: _bgColor,
                          swatches: _kBgSwatches,
                          onSelect: (c) {
                            setState(() => _bgColor = c);
                            _markDirty();
                          },
                        ),
                        const SizedBox(height: AppConstants.spacingLg),
                        const Divider(height: 1),
                        const SizedBox(height: AppConstants.spacingLg),
                        _ColorSwatchRow(
                          label: 'Eye color',
                          selected: _eyeColor,
                          swatches: _kEyeSwatches,
                          onSelect: (c) {
                            setState(() => _eyeColor = c);
                            _markDirty();
                          },
                        ),
                        const SizedBox(height: AppConstants.spacingLg),
                        const Divider(height: 1),
                        const SizedBox(height: AppConstants.spacingLg),
                        _ColorSwatchRow(
                          label: 'Mouth color',
                          selected: _mouthColor,
                          swatches: _kMouthSwatches,
                          onSelect: (c) {
                            setState(() => _mouthColor = c);
                            _markDirty();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spacingXxl),

                // ── Idle Display Mode ─────────────────────────────────
                Text('Idle Display Mode', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppConstants.spacingXxs),
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
                          onTap: () {
                            setState(() => _idleDisplayMode = option.$1);
                            _markDirty();
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppConstants.spacingXxl),

                // ── Idle Behavior ─────────────────────────────────────
                Text('Idle Behavior', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppConstants.spacingXxs),
                Text(
                  'How Aksa behaves when no one is talking to it.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: AppConstants.spacingMd),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Chat when idle'),
                        subtitle: const Text(
                          'Random fun facts, thoughts, and roasts',
                        ),
                        value: _idleChatEnabled,
                        onChanged: (v) {
                          setState(() => _idleChatEnabled = v);
                          _markDirty();
                        },
                      ),
                      if (_idleChatEnabled) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Chat frequency',
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ),
                              DropdownButton<String>(
                                value: _idleChatFrequency,
                                underline: const SizedBox.shrink(),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'rare',
                                    child: Text('Rare (15-25 min)'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'normal',
                                    child: Text('Normal (8-15 min)'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'frequent',
                                    child: Text('Often (3-8 min)'),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _idleChatFrequency = v);
                                  _markDirty();
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Animation speed',
                                style: theme.textTheme.bodyLarge,
                              ),
                            ),
                            DropdownButton<String>(
                              value: _idleAnimationSpeed,
                              underline: const SizedBox.shrink(),
                              items: const [
                                DropdownMenuItem(
                                  value: 'slow',
                                  child: Text('Slow (15-30s)'),
                                ),
                                DropdownMenuItem(
                                  value: 'normal',
                                  child: Text('Normal (8-20s)'),
                                ),
                                DropdownMenuItem(
                                  value: 'fast',
                                  child: Text('Fast (3-10s)'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => _idleAnimationSpeed = v);
                                _markDirty();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppConstants.spacingXxxl),
              ],
            ),
          ),

          // ── Sticky save bar ───────────────────────────────────────
          if (_dirty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Color swatch data ─────────────────────────────────────────────────────────

/// Background swatches — dark colors for the device display.
/// Brightened enough to be visually distinct as swatches on a phone screen.
const _kBgSwatches = [
  (Color(0xFF000000), 'Black'),
  (Color(0xFF001A4A), 'Navy'),
  (Color(0xFF1A0040), 'Purple'),
  (Color(0xFF004040), 'Teal'),
  (Color(0xFF004800), 'Forest'),
  (Color(0xFF400010), 'Crimson'),
  (Color(0xFF201830), 'Midnight'),
];

/// Mouth swatches — bright colors that stand out against dark backgrounds.
const _kMouthSwatches = [
  (Color(0xFFFFFFFF), 'White'),
  (Color(0xFF00FFFF), 'Cyan'),
  (Color(0xFFFFB0D0), 'Pink'),
  (Color(0xFFFFD060), 'Amber'),
  (Color(0xFF80FF80), 'Lime'),
  (Color(0xFF80C8FF), 'Sky'),
  (Color(0xFFC080FF), 'Violet'),
];

/// Eye body swatches — bright/pastel, high contrast against dark backgrounds.
const _kEyeSwatches = [
  (Color(0xFFDADCE6), 'White'),
  (Color(0xFF00FFFF), 'Cyan'),
  (Color(0xFFFFB0D0), 'Pink'),
  (Color(0xFFFFD060), 'Amber'),
  (Color(0xFF80FF80), 'Lime'),
  (Color(0xFF80C8FF), 'Sky'),
  (Color(0xFFC080FF), 'Violet'),
];

// ── Color swatch row ──────────────────────────────────────────────────────────

class _ColorSwatchRow extends StatelessWidget {
  final String label;
  final Color selected;
  final List<(Color, String)> swatches;
  final ValueChanged<Color> onSelect;

  const _ColorSwatchRow({
    required this.label,
    required this.selected,
    required this.swatches,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: AppConstants.spacingMd),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: swatches.map((entry) {
            final (color, name) = entry;
            final isSelected = color.toARGB32() == selected.toARGB32();

            return Tooltip(
              message: name,
              child: GestureDetector(
                onTap: () => onSelect(color),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? cs.primary : cs.outlineVariant,
                      width: isSelected ? 3 : 1.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.4),
                              blurRadius: 6,
                              spreadRadius: 1,
                            )
                          ]
                        : null,
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          size: 16,
                          color: color.computeLuminance() > 0.2
                              ? Colors.black87
                              : Colors.white,
                        )
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Idle mode options ─────────────────────────────────────────────────────────

const _idleModeOptions = [
  ('face', 'Face', 'Animated face — the default', Icons.face_rounded),
  ('clock', 'Clock', 'Large time and date display', Icons.access_time_rounded),
  (
    'status',
    'Status',
    'Connection info and system stats',
    Icons.bar_chart_rounded
  ),
];

// ── Face preview ──────────────────────────────────────────────────────────────

class _FacePreview extends StatelessWidget {
  final String faceStyle;
  final Color bgColor;
  final Color eyeColor;
  final Color mouthColor;

  const _FacePreview({
    required this.faceStyle,
    required this.bgColor,
    required this.eyeColor,
    required this.mouthColor,
  });

  @override
  Widget build(BuildContext context) {
    final isNova = faceStyle == 'nova';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      height: 120,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isNova) ...[
                  _RoundedEye(color: eyeColor),
                  const SizedBox(width: 28),
                  _RoundedEye(color: eyeColor),
                ] else ...[
                  _CircleEye(color: eyeColor),
                  const SizedBox(width: 28),
                  _CircleEye(color: eyeColor),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: mouthColor.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
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
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
            _RadioDot(selected: selected),
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
  final Color color;

  const _EyePreview.rounded({required this.color}) : rounded = true;
  const _EyePreview.circle({required this.color}) : rounded = false;

  @override
  Widget build(BuildContext context) {
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
              width: 14,
              height: 9,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 14,
              height: 9,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ] else ...[
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Container(
              width: 11,
              height: 11,
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
    final selected = value == groupValue;

    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(label),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: _RadioDot(selected: selected),
    );
  }
}

// ── Radio dot indicator ───────────────────────────────────────────────────────

class _RadioDot extends StatelessWidget {
  final bool selected;
  const _RadioDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final outline = Theme.of(context).colorScheme.outline;

    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: selected ? color : outline, width: 2),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
              ),
            )
          : null,
    );
  }
}
