import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/constants/api.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/storage_keys.dart';
import '../../../../core/di/injection.dart';
import '../../data/datasources/devices_remote_datasource.dart';
import '../../domain/repositories/devices_repository.dart';

/// Two-mode voice intercom page.
///
/// **Voice Message** — tap to record, tap again to stop; sends the
/// recording to the backend which encodes and plays it on the device.
///
/// **Live Intercom** — tap to start streaming; PCM audio is forwarded
/// in real time via the /intercom WebSocket to the device.
/// Walkie-talkie: when the device user holds the screen, the app
/// pauses its own stream, shows a "device listening" view, then plays
/// back the device's audio reply.
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
  int _originalVolume = 80;
  int _intercomVolume = 80;
  Timer? _volumeDebounce;

  // ── Talk to Aksa state ───────────────────────────────────────
  _AiInputState _aiState = _AiInputState.idle;
  String _aiTranscript = '';
  String _aiResponse = '';
  String? _aiError;
  Duration _aiDuration = Duration.zero;
  Timer? _aiTimer;
  _ReplyTarget _replyTarget = _ReplyTarget.device;
  final _appReplyPlayer = AudioPlayer();

  // ── Voice Message state ────────────────────────────────────────
  bool _msgRecording = false;
  bool _msgSending = false;
  String? _msgFilePath;
  Duration _msgDuration = Duration.zero;
  Timer? _msgTimer;

  // ── Live Intercom state ───────────────────────────────────────
  bool _liveActive = false;
  bool _liveConnecting = false;

  /// Device is holding its screen and recording a walkie-talkie reply.
  /// PCM streaming is paused while this is true.
  bool _deviceListening = false;

  /// The device's reply WAV is currently being played back on this device.
  bool _deviceReplying = false;

  WebSocketChannel? _wsChannel;
  StreamSubscription<dynamic>? _wsSub;
  StreamSubscription<Uint8List>? _pcmSub;
  Duration _liveDuration = Duration.zero;
  Timer? _liveTimer;
  final _replyPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _loadDevice();

    // Track when the reply audio finishes playing
    _replyPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _deviceReplying = false);
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _aiTimer?.cancel();
    _msgTimer?.cancel();
    _liveTimer?.cancel();
    _volumeDebounce?.cancel();
    _recorder.dispose();
    _replyPlayer.dispose();
    _appReplyPlayer.dispose();
    _stopLive(notify: false);
    super.dispose();
  }

  Future<void> _loadDevice() async {
    final result = await _repo.getDevice(widget.deviceId);
    result.fold(
      (_) {},
      (device) {
        final vol = (device.settingsJson['volume'] as num?)?.toInt() ?? 50;
        setState(() {
          _originalVolume = vol;
          _intercomVolume = vol;
        });
      },
    );
  }

  // ── Volume override ───────────────────────────────────────────

  void _onVolumeChanged(double value) {
    setState(() => _intercomVolume = value.round());
    _volumeDebounce?.cancel();
    _volumeDebounce = Timer(const Duration(milliseconds: 300), () {
      _datasource
          .sendVolumeOverride(widget.deviceId, _intercomVolume)
          .catchError((_) {});
    });
  }

  Future<void> _restoreVolume() async {
    try {
      await _datasource.sendVolumeOverride(widget.deviceId, _originalVolume);
    } catch (_) {}
  }

  // ── Voice Message ─────────────────────────────────────────────

  // ── Talk to Aksa ──────────────────────────────────────────────

  Future<void> _toggleAiRecording() async {
    if (_aiState == _AiInputState.recording) {
      await _stopAiRecording();
    } else {
      await _startAiRecording();
    }
  }

  Future<void> _startAiRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _showSnack('Microphone permission required');
      return;
    }

    final dir = await Directory.systemTemp.createTemp('aksa_ai_');
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

    _aiTimer?.cancel();
    _aiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _aiDuration += const Duration(seconds: 1));
    });

    setState(() {
      _aiState = _AiInputState.recording;
      _aiDuration = Duration.zero;
      _aiTranscript = '';
      _aiError = null;
    });
  }

  Future<void> _stopAiRecording() async {
    final path = await _recorder.stop();
    _aiTimer?.cancel();
    if (path == null) {
      setState(() => _aiState = _AiInputState.idle);
      return;
    }
    setState(() => _aiState = _AiInputState.processing);
    await _sendToAi(path);
  }

  Future<void> _sendToAi(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      setState(() { _aiState = _AiInputState.error; _aiError = 'Recording file not found'; });
      return;
    }
    final bytes = await file.readAsBytes();
    final target = _replyTarget == _ReplyTarget.app ? 'app' : 'device';

    final result = await _repo.sendVoiceInput(
      widget.deviceId,
      bytes,
      replyTarget: target,
    );
    if (!mounted) return;

    result.fold(
      (failure) => setState(() {
        _aiState = _AiInputState.error;
        _aiError = failure.message;
      }),
      (data) {
        if (data.transcript.isEmpty) {
          setState(() {
            _aiState = _AiInputState.error;
            _aiError = 'No speech recognised. Try speaking closer to the mic.';
          });
          return;
        }

        // App reply mode — show response text and play audio
        if (_replyTarget == _ReplyTarget.app) {
          if (data.hasAppReply) {
            setState(() {
              _aiState = _AiInputState.done;
              _aiTranscript = data.transcript;
              _aiResponse = data.response!;
            });
            // Play MP3 audio if available
            if (data.audio != null && data.audio!.isNotEmpty) {
              final audioBytes = base64Decode(data.audio!);
              _appReplyPlayer.play(BytesSource(
                Uint8List.fromList(audioBytes),
                mimeType: data.mimeType ?? 'audio/mpeg',
              ));
            }
          } else {
            setState(() {
              _aiState = _AiInputState.error;
              _aiTranscript = data.transcript;
              _aiError = 'Aksa could not generate a response.';
            });
          }
          return;
        }

        // Device reply mode — current behavior
        if (!data.dispatched) {
          setState(() {
            _aiState = _AiInputState.error;
            _aiTranscript = data.transcript;
            _aiError = 'Device is offline — Aksa could not respond.';
          });
        } else {
          setState(() {
            _aiState = _AiInputState.done;
            _aiTranscript = data.transcript;
          });
        }
      },
    );
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

      await _datasource
          .sendVolumeOverride(widget.deviceId, _intercomVolume)
          .catchError((_) {});

      final wsBase = ApiConstants.baseUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      final uri =
          Uri.parse('$wsBase/intercom?token=${Uri.encodeComponent(token)}');

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
    // Binary = WAV audio reply from device (walkie-talkie)
    if (msg is List<int>) {
      _replyPlayer.play(BytesSource(Uint8List.fromList(msg)));
      if (mounted) setState(() => _deviceReplying = true);
      return;
    }

    try {
      final json = jsonDecode(msg as String) as Map<String, dynamic>;
      final event = json['event'] as String?;

      switch (event) {
        case 'intercom:ready':
          _beginPcmStream();

        case 'intercom:device:talking':
          // Device user held the screen — pause our PCM stream and show
          // the "device listening" view so it's clear roles have flipped.
          if (mounted) {
            setState(() {
              _deviceListening = true;
              _deviceReplying = false;
            });
          }

        case 'intercom:device:done':
          // Device finished recording — resume our stream.
          // WAV binary arrives just before this event, so _deviceReplying
          // is already true and plays in the background.
          if (mounted) setState(() => _deviceListening = false);

        case 'error':
          final message =
              (json['data'] as Map?)?['message'] ?? 'Intercom error';
          _showSnack(message.toString());
          _stopLive();
      }
    } catch (_) {}
  }

  void _beginPcmStream() {
    _recorder
        .startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    )
        .then((stream) {
      _pcmSub = stream.listen((chunk) {
        // Pause forwarding while the device is recording its own reply.
        // Dropping chunks here is intentional — the device isn't playing
        // during its listen phase, so the gap is unnoticed.
        if (_wsChannel != null && _liveActive && !_deviceListening) {
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
    await _replyPlayer.stop();

    _restoreVolume();

    if (notify && mounted) {
      setState(() {
        _liveActive = false;
        _liveConnecting = false;
        _deviceListening = false;
        _deviceReplying = false;
      });
    }
  }

  // ── Helpers ───────────────────────────────────────────────────

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message), duration: AppConstants.snackBarDuration),
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
            Tab(icon: Icon(Icons.smart_toy_rounded), text: 'Talk to Aksa'),
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
            deviceListening: _deviceListening,
            deviceReplying: _deviceReplying,
            duration: _liveDuration,
            intercomVolume: _intercomVolume.toDouble(),
            originalVolume: _originalVolume,
            onToggle: _toggleLive,
            onVolumeChanged: _onVolumeChanged,
            formatDuration: _formatDuration,
            cs: cs,
          ),
          _TalkToAksaTab(
            state: _aiState,
            transcript: _aiTranscript,
            response: _aiResponse,
            duration: _aiDuration,
            error: _aiError,
            replyTarget: _replyTarget,
            onToggle: _toggleAiRecording,
            onReplyTargetChanged: (target) =>
                setState(() => _replyTarget = target),
            onReset: () {
              _appReplyPlayer.stop();
              setState(() {
                _aiState = _AiInputState.idle;
                _aiTranscript = '';
                _aiResponse = '';
                _aiError = null;
              });
            },
            formatDuration: _formatDuration,
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
  final bool deviceListening;
  final bool deviceReplying;
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
    required this.deviceListening,
    required this.deviceReplying,
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
    // While the device is listening or playing back its reply, swap the
    // entire centre section to make the role-flip obvious.
    if (deviceListening || deviceReplying) {
      return _DeviceReplyView(
        deviceListening: deviceListening,
        deviceReplying: deviceReplying,
        cs: cs,
      );
    }

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

          if (active)
            Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spacingMd),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.touch_app_rounded,
                    size: AppConstants.iconSm,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppConstants.spacingXs),
                  Text(
                    'Hold device screen to talk back',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),

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

// ── Device reply / listening view ─────────────────────────────────────────────

/// Full-screen overlay shown when the device has flipped the walkie-talkie
/// direction: either recording its own reply (listening) or playing it back.
class _DeviceReplyView extends StatefulWidget {
  final bool deviceListening;
  final bool deviceReplying;
  final ColorScheme cs;

  const _DeviceReplyView({
    required this.deviceListening,
    required this.deviceReplying,
    required this.cs,
  });

  @override
  State<_DeviceReplyView> createState() => _DeviceReplyViewState();
}

class _DeviceReplyViewState extends State<_DeviceReplyView>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween(begin: 1.0, end: 1.15).animate(
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
    final tt = Theme.of(context).textTheme;
    final cs = widget.cs;

    final isListening = widget.deviceListening;
    final color = isListening ? cs.secondary : cs.tertiary;
    final icon =
        isListening ? Icons.hearing_rounded : Icons.volume_up_rounded;
    final label = isListening ? 'Device is listening…' : 'Playing reply…';
    final sub = isListening
        ? 'Your mic is paused. Release the device screen when done.'
        : 'Your mic will resume automatically.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingXxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _scale,
              builder: (_, child) =>
                  Transform.scale(scale: _scale.value, child: child),
              child: Container(
                width: AppConstants.iconMassive * 1.5,
                height: AppConstants.iconMassive * 1.5,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2.5),
                ),
                child: Icon(icon, color: color, size: AppConstants.iconXxl),
              ),
            ),
            const SizedBox(height: AppConstants.spacingXxl),
            Text(
              label,
              style: tt.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacingMd),
            Text(
              sub,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
            Icon(_volumeIcon(volume),
                size: AppConstants.iconMd, color: cs.primary),
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
                        style: tt.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${volume.round()}',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [
                            const FontFeature.tabularFigures()
                          ],
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
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

// ── Talk to Aksa Tab ──────────────────────────────────────────────────────────

enum _AiInputState { idle, recording, processing, done, error }

enum _ReplyTarget { device, app }

class _TalkToAksaTab extends StatelessWidget {
  final _AiInputState state;
  final String transcript;
  final String response;
  final Duration duration;
  final String? error;
  final _ReplyTarget replyTarget;
  final VoidCallback onToggle;
  final ValueChanged<_ReplyTarget> onReplyTargetChanged;
  final VoidCallback onReset;
  final String Function(Duration) formatDuration;

  const _TalkToAksaTab({
    required this.state,
    required this.transcript,
    required this.response,
    required this.duration,
    required this.error,
    required this.replyTarget,
    required this.onToggle,
    required this.onReplyTargetChanged,
    required this.onReset,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isIdle = state == _AiInputState.idle;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.spacingXxl),
      child: Column(
        children: [
          // Reply target selector — only interactive when idle
          _ReplyTargetSelector(
            target: replyTarget,
            enabled: isIdle,
            onChanged: onReplyTargetChanged,
          ),
          const SizedBox(height: AppConstants.spacingXxl),

          // Status area
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: switch (state) {
              _AiInputState.idle => _buildHint(theme, cs),
              _AiInputState.recording => _buildRecording(theme, cs),
              _AiInputState.processing => _buildProcessing(theme, cs),
              _AiInputState.done => _buildDone(theme, cs),
              _AiInputState.error => _buildError(theme, cs),
            },
          ),

          const SizedBox(height: AppConstants.spacingXxxl),

          // Mic button — shown for idle and recording states
          if (state == _AiInputState.idle || state == _AiInputState.recording)
            _PulsingMicButton(
              recording: state == _AiInputState.recording,
              loading: false,
              onTap: onToggle,
            )
          else if (state == _AiInputState.processing)
            const SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          else
            FilledButton.tonal(
              onPressed: onReset,
              child: const Text('Ask again'),
            ),
        ],
      ),
    );
  }

  Widget _buildHint(ThemeData theme, ColorScheme cs) {
    final isApp = replyTarget == _ReplyTarget.app;
    return Column(
      key: const ValueKey('hint'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.smart_toy_rounded, size: 48, color: cs.primary),
        const SizedBox(height: AppConstants.spacingLg),
        Text(
          'Talk to Aksa',
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppConstants.spacingSm),
        Text(
          isApp
              ? 'Tap the mic, ask anything, and Aksa will reply right here.'
              : 'Tap the mic, ask anything, and Aksa will respond through the device speaker.',
          style:
              theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildRecording(ThemeData theme, ColorScheme cs) => Column(
        key: const ValueKey('recording'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatDuration(duration),
            style: theme.textTheme.displaySmall?.copyWith(
              color: cs.error,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Text(
            'Listening… tap to send',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      );

  Widget _buildProcessing(ThemeData theme, ColorScheme cs) => Column(
        key: const ValueKey('processing'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            replyTarget == _ReplyTarget.app
                ? 'Aksa is thinking…'
                : 'Transcribing…',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      );

  Widget _buildDone(ThemeData theme, ColorScheme cs) {
    final isApp = replyTarget == _ReplyTarget.app;

    return Column(
      key: const ValueKey('done'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // User's transcript
        if (transcript.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.person_rounded,
                  size: AppConstants.iconMd, color: cs.onSurfaceVariant),
              const SizedBox(width: AppConstants.spacingSm),
              Expanded(
                child: Text(
                  transcript,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingLg),
        ],

        // Aksa's response (app mode) or device confirmation
        if (isApp && response.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppConstants.spacingLg),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.smart_toy_rounded,
                        size: AppConstants.iconMd, color: cs.primary),
                    const SizedBox(width: AppConstants.spacingSm),
                    Text(
                      'Aksa',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: cs.primary),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spacingSm),
                Text(
                  response,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurface),
                ),
              ],
            ),
          ),
        ] else if (!isApp) ...[
          Icon(Icons.check_circle_rounded, size: 40, color: cs.primary),
          const SizedBox(height: AppConstants.spacingMd),
          Text(
            'Aksa is responding on your device…',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildError(ThemeData theme, ColorScheme cs) => Column(
        key: const ValueKey('error'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 40, color: cs.error),
          const SizedBox(height: AppConstants.spacingMd),
          if (transcript.isNotEmpty) ...[
            Text(
              '"$transcript"',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontStyle: FontStyle.italic,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacingSm),
          ],
          Text(
            error ?? 'Something went wrong',
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.error),
            textAlign: TextAlign.center,
          ),
        ],
      );
}

// ── Reply target selector ────────────────────────────────────────────────────

class _ReplyTargetSelector extends StatelessWidget {
  final _ReplyTarget target;
  final bool enabled;
  final ValueChanged<_ReplyTarget> onChanged;

  const _ReplyTargetSelector({
    required this.target,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_ReplyTarget>(
      segments: const [
        ButtonSegment(
          value: _ReplyTarget.device,
          label: Text('Device'),
          icon: Icon(Icons.speaker_rounded),
        ),
        ButtonSegment(
          value: _ReplyTarget.app,
          label: Text('This Phone'),
          icon: Icon(Icons.phone_android_rounded),
        ),
      ],
      selected: {target},
      onSelectionChanged: enabled
          ? (selection) => onChanged(selection.first)
          : null,
    );
  }
}
