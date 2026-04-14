import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/constants/api.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/storage_keys.dart';
import '../../../../core/di/injection.dart';
import '../../data/datasources/devices_remote_datasource.dart';
import '../../domain/entities/device_entity.dart';
import '../../domain/repositories/devices_repository.dart';

/// Two-mode voice intercom page.
///
/// **Voice Message** — tap to record, tap again to stop; sends the
/// recording to the backend which encodes and plays it on the device.
///
/// **Live Intercom** — tap to start streaming; PCM audio is forwarded
/// in real time via the /intercom WebSocket to the device.
/// Includes a temporary volume slider that overrides the device's
/// global volume setting for the duration of the session, then
/// restores it automatically when done.
class VoiceIntercomPage extends StatefulWidget {
  final String deviceId;
  const VoiceIntercomPage({super.key, required this.deviceId});

  @override
  State<VoiceIntercomPage> createState() => _VoiceIntercomPageState();
}

class _VoiceIntercomPageState extends State<VoiceIntercomPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _recorder = AudioRecorder();
  final _storage = sl<FlutterSecureStorage>();
  final _repo = sl<DevicesRepository>();
  final _datasource = sl<DevicesRemoteDatasource>();

  // ── Device / volume ───────────────────────────────────────────
  Device? _device;
  int _originalVolume = 80;  // restored after intercom
  int _intercomVolume = 80;  // slider value during intercom
  Timer? _volumeDebounce;

  // ── Voice Message state ────────────────────────────────────────
  bool _msgRecording = false;
  bool _msgSending = false;
  String? _msgFilePath;
  Duration _msgDuration = Duration.zero;
  Timer? _msgTimer;

  // ── Live Intercom state ───────────────────────────────────────
  bool _liveActive = false;
  bool _liveConnecting = false;
  WebSocketChannel? _wsChannel;
  StreamSubscription<dynamic>? _wsSub;
  StreamSubscription<Uint8List>? _pcmSub;
  Duration _liveDuration = Duration.zero;
  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadDevice();
  }

  @override
  void dispose() {
    _tab.dispose();
    _msgTimer?.cancel();
    _liveTimer?.cancel();
    _volumeDebounce?.cancel();
    _recorder.dispose();
    _stopLive(notify: false);
    super.dispose();
  }

  Future<void> _loadDevice() async {
    final result = await _repo.getDevice(widget.deviceId);
    result.fold(
      (_) {},
      (device) {
        final vol = (device.settingsJson['volume'] as num?)?.toInt() ?? 80;
        setState(() {
          _device = device;
          _originalVolume = vol;
          _intercomVolume = vol;
        });
      },
    );
  }

  // ── Volume override ───────────────────────────────────────────

  void _onVolumeChanged(double value) {
    setState(() => _intercomVolume = value.round());
    // Debounce: only send 300ms after the user stops dragging.
    _volumeDebounce?.cancel();
    _volumeDebounce = Timer(const Duration(milliseconds: 300), () {
      _datasource.sendVolumeOverride(widget.deviceId, _intercomVolume)
          .catchError((_) {});
    });
  }

  Future<void> _restoreVolume() async {
    try {
      await _datasource.sendVolumeOverride(widget.deviceId, _originalVolume);
    } catch (_) {}
  }

  // ── Voice Message ─────────────────────────────────────────────

  Future<void> _toggleMsgRecording() async {
    if (_msgRecording) {
      await _stopMsgRecording();
    } else {
      await _startMsgRecording();
    }
  }

  Future<void> _startMsgRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _showSnack('Microphone permission required');
      return;
    }

    final dir = await Directory.systemTemp.createTemp('aksa_voice_');
    final path = '${dir.path}/voice.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
      ),
      path: path,
    );

    _msgTimer?.cancel();
    _msgTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _msgDuration += const Duration(seconds: 1));
    });

    setState(() {
      _msgRecording = true;
      _msgFilePath = path;
      _msgDuration = Duration.zero;
    });
  }

  Future<void> _stopMsgRecording() async {
    final path = await _recorder.stop();
    _msgTimer?.cancel();
    setState(() {
      _msgRecording = false;
      _msgFilePath = path;
    });
  }

  Future<void> _sendVoiceMessage() async {
    final path = _msgFilePath;
    if (path == null) return;

    final file = File(path);
    if (!file.existsSync()) {
      _showSnack('Recording file not found');
      return;
    }

    setState(() => _msgSending = true);
    try {
      final bytes = await file.readAsBytes();
      final result = await _repo.sendVoiceMessage(widget.deviceId, bytes);
      result.fold(
        (failure) => _showSnack('Failed: ${failure.message}'),
        (playing) => _showSnack(
          playing ? 'Playing on device!' : 'Device is offline',
        ),
      );
      setState(() => _msgFilePath = null);
    } finally {
      if (mounted) setState(() => _msgSending = false);
    }
  }

  // ── Live Intercom ─────────────────────────────────────────────

  Future<void> _toggleLive() async {
    if (_liveActive) {
      await _stopLive();
    } else {
      await _startLive();
    }
  }

  Future<void> _startLive() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _showSnack('Microphone permission required');
      return;
    }

    setState(() => _liveConnecting = true);

    try {
      final token = await _storage.read(key: StorageKeys.accessToken);
      if (token == null) {
        _showSnack('Not authenticated');
        setState(() => _liveConnecting = false);
        return;
      }

      // Push the intercom volume before opening the stream.
      // If it's already at original, this is a no-op on the device.
      await _datasource.sendVolumeOverride(widget.deviceId, _intercomVolume)
          .catchError((_) {});

      final wsBase = ApiConstants.baseUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      final uri = Uri.parse('$wsBase/intercom?token=${Uri.encodeComponent(token)}');

      _wsChannel = WebSocketChannel.connect(uri);
      _wsSub = _wsChannel!.stream.listen(
        _onWsMessage,
        onError: (_) => _stopLive(),
        onDone: () => _stopLive(),
      );

      _wsChannel!.sink.add(jsonEncode({
        'event': 'intercom:start',
        'data': {'deviceId': widget.deviceId},
      }));
    } catch (e) {
      _showSnack('Connection failed: $e');
      setState(() => _liveConnecting = false);
    }
  }

  void _onWsMessage(dynamic msg) {
    try {
      final json = jsonDecode(msg as String) as Map<String, dynamic>;
      if (json['event'] == 'intercom:ready') {
        _beginPcmStream();
      } else if (json['event'] == 'error') {
        final message = (json['data'] as Map?)?['message'] ?? 'Intercom error';
        _showSnack(message.toString());
        _stopLive();
      }
    } catch (_) {}
  }

  void _beginPcmStream() {
    _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    ).then((stream) {
      _pcmSub = stream.listen((chunk) {
        if (_wsChannel != null && _liveActive) {
          _wsChannel!.sink.add(chunk);
        }
      });

      _liveTimer?.cancel();
      _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _liveDuration += const Duration(seconds: 1));
      });

      if (mounted) {
        setState(() {
          _liveConnecting = false;
          _liveActive = true;
          _liveDuration = Duration.zero;
        });
      }
    }).catchError((e) {
      _showSnack('Microphone error: $e');
      _stopLive();
    });
  }

  Future<void> _stopLive({bool notify = true}) async {
    _liveTimer?.cancel();
    _volumeDebounce?.cancel();

    await _pcmSub?.cancel();
    _pcmSub = null;

    if (_wsChannel != null) {
      try {
        _wsChannel!.sink.add(jsonEncode({'event': 'intercom:stop'}));
        await _wsChannel!.sink.close();
      } catch (_) {}
      _wsChannel = null;
    }

    await _wsSub?.cancel();
    _wsSub = null;

    await _recorder.stop();

    // Restore original volume — fire and forget.
    _restoreVolume();

    if (notify && mounted) {
      setState(() {
        _liveActive = false;
        _liveConnecting = false;
      });
    }
  }

  // ── Helpers ───────────────────────────────────────────────────

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: AppConstants.snackBarDuration),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Intercom'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.mic_rounded), text: 'Voice Message'),
            Tab(icon: Icon(Icons.surround_sound_rounded), text: 'Live'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _VoiceMessageTab(
            recording: _msgRecording,
            sending: _msgSending,
            hasRecording: _msgFilePath != null,
            duration: _msgDuration,
            onToggle: _toggleMsgRecording,
            onSend: _sendVoiceMessage,
            onDiscard: () => setState(() {
              _msgFilePath = null;
              _msgDuration = Duration.zero;
            }),
            formatDuration: _formatDuration,
          ),
          _LiveIntercomTab(
            active: _liveActive,
            connecting: _liveConnecting,
            duration: _liveDuration,
            intercomVolume: _intercomVolume.toDouble(),
            originalVolume: _originalVolume,
            onToggle: _toggleLive,
            onVolumeChanged: _onVolumeChanged,
            formatDuration: _formatDuration,
            cs: cs,
          ),
        ],
      ),
    );
  }
}

// ── Voice Message Tab ─────────────────────────────────────────────────────────

class _VoiceMessageTab extends StatelessWidget {
  final bool recording;
  final bool sending;
  final bool hasRecording;
  final Duration duration;
  final VoidCallback onToggle;
  final VoidCallback onSend;
  final VoidCallback onDiscard;
  final String Function(Duration) formatDuration;

  const _VoiceMessageTab({
    required this.recording,
    required this.sending,
    required this.hasRecording,
    required this.duration,
    required this.onToggle,
    required this.onSend,
    required this.onDiscard,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(AppConstants.spacingXxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            recording
                ? 'Recording…'
                : hasRecording
                    ? 'Ready to send'
                    : 'Tap to record a voice message',
            style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          if (recording || hasRecording)
            Text(
              formatDuration(duration),
              style: tt.displaySmall?.copyWith(
                fontFeatures: [const FontFeature.tabularFigures()],
                color: recording ? cs.error : cs.onSurface,
              ),
            ),
          const SizedBox(height: AppConstants.spacingHuge),
          _PulsingMicButton(
            recording: recording,
            onTap: hasRecording && !recording ? null : onToggle,
          ),
          const SizedBox(height: AppConstants.spacingXxl),
          if (hasRecording && !recording) ...[
            FilledButton.icon(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(sending ? 'Sending…' : 'Send to Device'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(220, AppConstants.buttonHeight),
              ),
            ),
            const SizedBox(height: AppConstants.spacingMd),
            TextButton.icon(
              onPressed: onDiscard,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Discard'),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Live Intercom Tab ─────────────────────────────────────────────────────────

class _LiveIntercomTab extends StatelessWidget {
  final bool active;
  final bool connecting;
  final Duration duration;
  final double intercomVolume;
  final int originalVolume;
  final VoidCallback onToggle;
  final ValueChanged<double> onVolumeChanged;
  final String Function(Duration) formatDuration;
  final ColorScheme cs;

  const _LiveIntercomTab({
    required this.active,
    required this.connecting,
    required this.duration,
    required this.intercomVolume,
    required this.originalVolume,
    required this.onToggle,
    required this.onVolumeChanged,
    required this.formatDuration,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(AppConstants.spacingXxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            active
                ? 'Live — device is hearing you'
                : connecting
                    ? 'Connecting…'
                    : 'Tap to start live intercom',
            style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.spacingMd),
          if (active)
            Text(
              formatDuration(duration),
              style: tt.displaySmall?.copyWith(
                fontFeatures: [const FontFeature.tabularFigures()],
                color: cs.primary,
              ),
            ),
          const SizedBox(height: AppConstants.spacingHuge),

          _PulsingMicButton(
            recording: active,
            loading: connecting,
            onTap: connecting ? null : onToggle,
            color: active ? cs.primary : null,
          ),

          const SizedBox(height: AppConstants.spacingXxl),

          // Volume override — shown whenever the tab is active (not just during
          // live session) so the user can set it before starting.
          _VolumeOverrideSlider(
            volume: intercomVolume,
            originalVolume: originalVolume,
            isLive: active,
            onChanged: onVolumeChanged,
            cs: cs,
          ),
        ],
      ),
    );
  }
}

// ── Volume override slider ────────────────────────────────────────────────────

class _VolumeOverrideSlider extends StatelessWidget {
  final double volume;
  final int originalVolume;
  final bool isLive;
  final ValueChanged<double> onChanged;
  final ColorScheme cs;

  const _VolumeOverrideSlider({
    required this.volume,
    required this.originalVolume,
    required this.isLive,
    required this.onChanged,
    required this.cs,
  });

  IconData _volumeIcon(double v) {
    if (v == 0) return Icons.volume_off_rounded;
    if (v < 40) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final changed = volume.round() != originalVolume;

    return Column(
      children: [
        Row(
          children: [
            Icon(_volumeIcon(volume), size: AppConstants.iconMd, color: cs.primary),
            const SizedBox(width: AppConstants.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Intercom volume',
                        style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${volume.round()}',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [const FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      value: volume,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      onChanged: onChanged,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (changed)
          Padding(
            padding: const EdgeInsets.only(top: AppConstants.spacingXs),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline,
                    size: AppConstants.iconSm, color: cs.onSurfaceVariant),
                const SizedBox(width: AppConstants.spacingXs),
                Text(
                  'Restores to $originalVolume when intercom ends',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        if (!isLive && !changed)
          Padding(
            padding: const EdgeInsets.only(top: AppConstants.spacingXs),
            child: Text(
              'Adjust before or during the live session.\nRestored automatically when you stop.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

// ── Shared mic button with pulse animation ────────────────────────────────────

class _PulsingMicButton extends StatefulWidget {
  final bool recording;
  final bool loading;
  final VoidCallback? onTap;
  final Color? color;

  const _PulsingMicButton({
    required this.recording,
    this.loading = false,
    this.onTap,
    this.color,
  });

  @override
  State<_PulsingMicButton> createState() => _PulsingMicButtonState();
}

class _PulsingMicButtonState extends State<_PulsingMicButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _scale = Tween(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = widget.recording;
    final bg = active ? (widget.color ?? cs.error) : cs.primaryContainer;
    final fg = active ? Colors.white : cs.onPrimaryContainer;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(
          scale: active ? _scale.value : 1.0,
          child: child,
        ),
        child: Container(
          width: AppConstants.iconMassive * 1.5,
          height: AppConstants.iconMassive * 1.5,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: bg.withValues(alpha: 0.4),
                      blurRadius: 24,
                      spreadRadius: 8,
                    )
                  ]
                : null,
          ),
          child: widget.loading
              ? Center(
                  child: CircularProgressIndicator(
                    color: fg,
                    strokeWidth: 2.5,
                  ),
                )
              : Icon(
                  active ? Icons.stop_rounded : Icons.mic_rounded,
                  color: fg,
                  size: AppConstants.iconXxl,
                ),
        ),
      ),
    );
  }
}
