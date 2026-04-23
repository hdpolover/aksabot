import 'dart:io';
import 'package:equatable/equatable.dart';

abstract class VisionEvent extends Equatable {
  const VisionEvent();
  @override
  List<Object?> get props => [];
}

class LoadProfiles extends VisionEvent {
  const LoadProfiles();
}

class EnrollFromFile extends VisionEvent {
  final File photo;
  final String name;
  const EnrollFromFile({required this.photo, required this.name});
  @override
  List<Object?> get props => [photo.path, name];
}

class EnrollFromFiles extends VisionEvent {
  final List<File> photos;
  final String name;
  const EnrollFromFiles({required this.photos, required this.name});
  @override
  List<Object?> get props => [photos.map((f) => f.path).toList(), name];
}

class TriggerDeskCapture extends VisionEvent {
  final String cameraDeviceId;
  final String name;
  const TriggerDeskCapture({required this.cameraDeviceId, required this.name});
  @override
  List<Object?> get props => [cameraDeviceId, name];
}

class DeleteProfile extends VisionEvent {
  final String profileId;
  const DeleteProfile({required this.profileId});
  @override
  List<Object?> get props => [profileId];
}

class ToggleVisionMode extends VisionEvent {
  final String deviceId;
  final String mode; // 'always' | 'conversation'
  const ToggleVisionMode({required this.deviceId, required this.mode});
  @override
  List<Object?> get props => [deviceId, mode];
}
