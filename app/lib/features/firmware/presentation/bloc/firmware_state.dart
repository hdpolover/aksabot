import '../../domain/entities/firmware_release.dart';
import '../../domain/entities/ota_status.dart';

abstract class FirmwareState {
  const FirmwareState();
}

class FirmwareInitial extends FirmwareState {
  const FirmwareInitial();
}

class FirmwareLoading extends FirmwareState {
  const FirmwareLoading();
}

class FirmwareLoaded extends FirmwareState {
  /// null = no releases uploaded to the backend yet
  final FirmwareRelease? latest;
  final OtaStatus otaStatus;

  const FirmwareLoaded({required this.latest, required this.otaStatus});

  FirmwareLoaded copyWith({FirmwareRelease? latest, OtaStatus? otaStatus}) {
    return FirmwareLoaded(
      latest: latest ?? this.latest,
      otaStatus: otaStatus ?? this.otaStatus,
    );
  }
}

class FirmwareTriggerInProgress extends FirmwareState {
  const FirmwareTriggerInProgress();
}

class FirmwareError extends FirmwareState {
  final String message;
  const FirmwareError(this.message);
}
