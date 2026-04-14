abstract class FirmwareEvent {
  const FirmwareEvent();
}

/// Load the latest available release + current OTA status.
class FirmwarePageOpened extends FirmwareEvent {
  final String deviceId;
  const FirmwarePageOpened(this.deviceId);
}

/// User tapped "Update Now".
class FirmwareOtaTriggered extends FirmwareEvent {
  final String deviceId;
  final String? releaseId;
  const FirmwareOtaTriggered(this.deviceId, {this.releaseId});
}

/// Polling tick while OTA is in progress.
class FirmwareOtaStatusPolled extends FirmwareEvent {
  final String deviceId;
  const FirmwareOtaStatusPolled(this.deviceId);
}
