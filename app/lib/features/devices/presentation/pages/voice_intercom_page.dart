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
import '../../domain/repositories/devices_repository.dart';

/// Two-mode voice intercom page.
///
/// **Voice Message** — tap to record, tap again to stop; sends the
/// recording to the backend which encodes and plays it on the device.
///
/// **Live Intercom** — tap to start streaming; PCM audio is forwarded
/// in real time via the /intercom WebSocket to the device.
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
  }

  @override
  void dispose() {
    _tab.dispose();
    _msgTimer?.cancel();
    _liveTimer?.cancel();
    _recorder.dispose();
    _stopLive(notify: false);
    super.dispose();
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
          playing ? 'Playing on device!' : 'Device is offline — message queued',
        ),
      );
      // Reset for next recording
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

      // Derive WS URL from API base URL (http→ws, https→wss)
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

      // Send start event — gateway will verify device ownership
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
            onToggle: _toggleLive,
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
          // Status label
          Text(
            recording
                ? 'Recording…'
                : hasRecording
                    ? 'Ready to send'
                    : 'Tap to record a voice message',
            style: tt.titleMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),

          // Timer
          if (recording || hasRecording)
            Text(
              formatDuration(duration),
              style: tt.displaySmall?.copyWith(
                fontFeatures: [const FontFeature.tabularFigures()],
                color: recording ? cs.error : cs.onSurface,
              ),
            ),
          const SizedBox(height: AppConstants.spacingHuge),

          // Mic button
          _PulsingMicButton(
            recording: recording,
            onTap: hasRecording && !recording ? null : onToggle,
          ),

          const SizedBox(height: AppConstants.spacingXxl),

          // Send / Discard
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
  final VoidCallback onToggle;
  final String Function(Duration) formatDuration;
  final ColorScheme cs;

  const _LiveIntercomTab({
    required this.active,
    required this.connecting,
    required this.duration,
    required this.onToggle,
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
          Text(
            'Your voice is streamed directly to the device in real time.\n'
            'The device plays it as you speak.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
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
