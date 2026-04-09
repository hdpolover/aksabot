import 'package:flutter/material.dart';

/// Display & Face settings — planned UI (Phase 2, TFT dependent).
class DisplayFacePage extends StatefulWidget {
  final String deviceId;
  const DisplayFacePage({super.key, required this.deviceId});

  @override
  State<DisplayFacePage> createState() => _DisplayFacePageState();
}

class _DisplayFacePageState extends State<DisplayFacePage> {
  String _faceStyle = 'default';
  String _idleMode = 'face';
  double _brightness = 80;
  bool _autoDim = true;
  Color _eyeColor = const Color(0xFF6366F1);
  Color _bgColor = Colors.black;

  static const _colorOptions = [
    Color(0xFF6366F1), // Indigo
    Color(0xFF3B82F6), // Blue
    Color(0xFF10B981), // Green
    Color(0xFFF59E0B), // Amber
    Color(0xFFEF4444), // Red
    Color(0xFF8B5CF6), // Purple
    Color(0xFFEC4899), // Pink
    Color(0xFFFFFFFF), // White
    Color(0xFF000000), // Black
  ];

  void _showColorPicker(
    BuildContext context,
    String title,
    Color current,
    ValueChanged<Color> onSelected,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _colorOptions.map((color) {
            final isSelected = color == current;
            return GestureDetector(
              onTap: () {
                onSelected(color);
                Navigator.pop(ctx);
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: isSelected ? 3 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Display & Face')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Face preview
          Card(
            color: Colors.black,
            child: SizedBox(
              height: 160,
              child: Center(
                child: Text(
                  '(  o   o  )\n    ───',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineLarge?.copyWith(
                    color: colors.primary,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Face style
          Text('Face Style', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: RadioGroup<String>(
              groupValue: _faceStyle,
              onChanged: (v) => setState(() { if (v != null) _faceStyle = v; }),
              child: Column(
                children: [
                  for (final style in [
                    ('default', 'Default'),
                    ('minimal', 'Minimal'),
                    ('kawaii', 'Kawaii'),
                    ('pixel', 'Pixel'),
                  ])
                    ListTile(
                      title: Text(style.$2),
                      leading: Radio<String>(value: style.$1),
                      onTap: () => setState(() => _faceStyle = style.$1),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Idle display mode
          Text('Idle Display Mode', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: RadioGroup<String>(
              groupValue: _idleMode,
              onChanged: (v) => setState(() { if (v != null) _idleMode = v; }),
              child: Column(
                children: [
                  for (final mode in [
                    ('face', 'Face', Icons.face),
                    ('clock', 'Clock', Icons.access_time),
                    ('pomodoro', 'Pomodoro timer', Icons.timer),
                    ('weather', 'Weather', Icons.cloud),
                    ('off', 'Screen off', Icons.power_settings_new),
                  ])
                    ListTile(
                      leading: Radio<String>(value: mode.$1),
                      title: Text(mode.$2),
                      trailing: Icon(mode.$3),
                      onTap: () => setState(() => _idleMode = mode.$1),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Colors
          Text('Colors', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  title: const Text('Eye color'),
                  trailing: GestureDetector(
                    onTap: () => _showColorPicker(
                      context,
                      'Eye color',
                      _eyeColor,
                      (c) => setState(() => _eyeColor = c),
                    ),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _eyeColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.outlineVariant),
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Background'),
                  trailing: GestureDetector(
                    onTap: () => _showColorPicker(
                      context,
                      'Background',
                      _bgColor,
                      (c) => setState(() => _bgColor = c),
                    ),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _bgColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.outlineVariant),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Brightness
          Text('Brightness', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Slider(
                    value: _brightness,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '${_brightness.round()}%',
                    onChanged: (v) => setState(() => _brightness = v),
                  ),
                  SwitchListTile(
                    title: const Text('Auto-dim at night'),
                    value: _autoDim,
                    onChanged: (v) => setState(() => _autoDim = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Requires Phase 2 hardware (TFT display).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
