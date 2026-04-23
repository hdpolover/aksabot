import 'package:equatable/equatable.dart';
import 'package:aksabot/features/devices/data/repositories/vision_repository.dart';

abstract class VisionState extends Equatable {
  const VisionState();
  @override
  List<Object?> get props => [];
}

class VisionInitial extends VisionState {
  const VisionInitial();
}

class VisionLoading extends VisionState {
  const VisionLoading();
}

class VisionLoaded extends VisionState {
  final List<FaceProfileModel> profiles;
  const VisionLoaded({required this.profiles});
  @override
  List<Object?> get props => [profiles];
}

class VisionError extends VisionState {
  final String message;
  const VisionError({required this.message});
  @override
  List<Object?> get props => [message];
}

class VisionEnrolling extends VisionState {
  const VisionEnrolling();
}

class VisionEnrollSuccess extends VisionState {
  final String name;
  const VisionEnrollSuccess({required this.name});
  @override
  List<Object?> get props => [name];
}
