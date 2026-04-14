import 'dart:typed_data';

import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/device_entity.dart';

abstract class DevicesRepository {
  Future<Either<Failure, List<Device>>> getDevices();
  Future<Either<Failure, Device>> getDevice(String id);
  Future<Either<Failure, Device>> createDevice({String? name});
  Future<Either<Failure, Device>> updateSettings(String id, Map<String, dynamic> settings);
  Future<Either<Failure, Device>> claimByToken(String deviceToken);
  Future<Either<Failure, void>> requestProvision(String id);
  Future<Either<Failure, void>> reportPresence(
    String id,
    String event, {
    int awayDurationSeconds = 0,
  });
  Future<Either<Failure, void>> deleteDevice(String id);
  Future<Either<Failure, void>> factoryReset(String id);
  Future<Either<Failure, Map<String, dynamic>>> getStats(String id);
  Future<Either<Failure, bool>> pushVoicePreviewToDevice(
    String id, {
    String? language,
    String? voicePreset,
    double? speed,
    double? stability,
    String? text,
  });

  Future<Either<Failure, Uint8List>> previewVoice(
    String id, {
    String? language,
    String? voicePreset,
    double? speed,
    double? stability,
    String? text,
  });

  /// Send a pre-recorded voice message (raw PCM or WAV) to the device.
  /// Returns true if the device was online and played the audio.
  Future<Either<Failure, bool>> sendVoiceMessage(String id, Uint8List audioBytes);

  /// Upload a compressed image to the backend and push it to the device display.
  /// [imageBytes] must be JPEG-encoded. [durationMs] controls auto-return time.
  Future<Either<Failure, void>> pushImage(
    String id,
    Uint8List imageBytes, {
    int durationMs = 10000,
  });

  /// Send a voice recording to the AI pipeline (STT → LLM → TTS → device speaker).
  /// Returns the recognised transcript and whether the pipeline was dispatched.
  Future<Either<Failure, VoiceInputResult>> sendVoiceInput(String id, Uint8List audioBytes);

  /// Request fresh logs from the device (sends log:fetch over WebSocket).
  /// Waits up to ~3s for the device to respond.
  /// Returns [DeviceLogs] on success, or a failure if the device is offline.
  Future<Either<Failure, DeviceLogs>> fetchLogs(String id);
}

class VoiceInputResult {
  final String transcript;
  final bool dispatched;

  const VoiceInputResult({required this.transcript, required this.dispatched});

  factory VoiceInputResult.fromJson(Map<String, dynamic> json) => VoiceInputResult(
        transcript: json['transcript'] as String? ?? '',
        dispatched: json['dispatched'] as bool? ?? false,
      );
}

class DeviceLogs {
  final String? text;
  final int bytes;
  final DateTime? fetchedAt;
  final bool offline;

  const DeviceLogs({
    required this.text,
    required this.bytes,
    this.fetchedAt,
    this.offline = false,
  });

  bool get hasData => text != null && text!.isNotEmpty;

  factory DeviceLogs.fromJson(Map<String, dynamic> json) {
    return DeviceLogs(
      text: json['text'] as String?,
      bytes: json['bytes'] as int? ?? 0,
      offline: json['offline'] as bool? ?? false,
      fetchedAt: json['fetchedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['fetchedAt'] as int)
          : null,
    );
  }
}
