import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:aksabot/features/devices/data/repositories/vision_repository.dart';
import 'vision_event.dart';
import 'vision_state.dart';

class VisionBloc extends Bloc<VisionEvent, VisionState> {
  final VisionRepository repository;

  VisionBloc({required this.repository}) : super(const VisionInitial()) {
    on<LoadProfiles>(_onLoadProfiles);
    on<EnrollFromFile>(_onEnrollFromFile);
    on<TriggerDeskCapture>(_onTriggerDeskCapture);
    on<DeleteProfile>(_onDeleteProfile);
    on<ToggleVisionMode>(_onToggleVisionMode);
  }

  Future<void> _onLoadProfiles(LoadProfiles event, Emitter<VisionState> emit) async {
    emit(const VisionLoading());
    try {
      final profiles = await repository.getProfiles();
      emit(VisionLoaded(profiles: profiles));
    } catch (e) {
      emit(VisionError(message: e.toString()));
    }
  }

  Future<void> _onEnrollFromFile(EnrollFromFile event, Emitter<VisionState> emit) async {
    emit(const VisionEnrolling());
    try {
      await repository.enrollFromFile(photo: event.photo, name: event.name);
      emit(VisionEnrollSuccess(name: event.name));
      final profiles = await repository.getProfiles();
      emit(VisionLoaded(profiles: profiles));
    } catch (e) {
      emit(VisionError(message: e.toString()));
    }
  }

  Future<void> _onTriggerDeskCapture(TriggerDeskCapture event, Emitter<VisionState> emit) async {
    emit(const VisionEnrolling());
    try {
      await repository.triggerDeskCapture(
        cameraDeviceId: event.cameraDeviceId,
        name: event.name,
      );
      emit(VisionEnrollSuccess(name: event.name));
      final profiles = await repository.getProfiles();
      emit(VisionLoaded(profiles: profiles));
    } catch (e) {
      emit(VisionError(message: e.toString()));
    }
  }

  Future<void> _onDeleteProfile(DeleteProfile event, Emitter<VisionState> emit) async {
    emit(const VisionLoading());
    try {
      await repository.deleteProfile(event.profileId);
      final profiles = await repository.getProfiles();
      emit(VisionLoaded(profiles: profiles));
    } catch (e) {
      emit(VisionError(message: e.toString()));
    }
  }

  Future<void> _onToggleVisionMode(ToggleVisionMode event, Emitter<VisionState> emit) async {
    emit(const VisionLoading());
    try {
      await repository.setVisionMode(deviceId: event.deviceId, mode: event.mode);
      final profiles = await repository.getProfiles();
      emit(VisionLoaded(profiles: profiles));
    } catch (e) {
      emit(VisionError(message: e.toString()));
    }
  }
}
