import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/device_entity.dart';
import '../../domain/repositories/devices_repository.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

abstract class DevicesEvent extends Equatable {
  const DevicesEvent();

  @override
  List<Object?> get props => [];
}

class LoadDevices extends DevicesEvent {
  const LoadDevices();
}

class LoadDevice extends DevicesEvent {
  final String deviceId;
  const LoadDevice(this.deviceId);

  @override
  List<Object?> get props => [deviceId];
}

class CreateDevice extends DevicesEvent {
  final String? name;
  const CreateDevice({this.name});

  @override
  List<Object?> get props => [name];
}

class DeleteDevice extends DevicesEvent {
  final String deviceId;
  const DeleteDevice(this.deviceId);

  @override
  List<Object?> get props => [deviceId];
}

class UpdateSettings extends DevicesEvent {
  final String deviceId;
  final Map<String, dynamic> settings;
  const UpdateSettings(this.deviceId, this.settings);

  @override
  List<Object?> get props => [deviceId, settings];
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

abstract class DevicesState extends Equatable {
  const DevicesState();

  @override
  List<Object?> get props => [];
}

class DevicesInitial extends DevicesState {
  const DevicesInitial();
}

class DevicesLoading extends DevicesState {
  const DevicesLoading();
}

class DevicesLoaded extends DevicesState {
  final List<Device> devices;
  const DevicesLoaded(this.devices);

  @override
  List<Object?> get props => [devices];
}

class DeviceDetailLoaded extends DevicesState {
  final Device device;
  const DeviceDetailLoaded(this.device);

  @override
  List<Object?> get props => [device];
}

class DevicesError extends DevicesState {
  final String message;
  const DevicesError(this.message);

  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// BLoC
// ---------------------------------------------------------------------------

class DevicesBloc extends Bloc<DevicesEvent, DevicesState> {
  final DevicesRepository _repository;

  DevicesBloc(this._repository) : super(const DevicesInitial()) {
    on<LoadDevices>(_onLoadDevices);
    on<LoadDevice>(_onLoadDevice);
    on<CreateDevice>(_onCreateDevice);
    on<DeleteDevice>(_onDeleteDevice);
    on<UpdateSettings>(_onUpdateSettings);
  }

  Future<void> _onLoadDevices(
    LoadDevices event,
    Emitter<DevicesState> emit,
  ) async {
    emit(const DevicesLoading());
    final result = await _repository.getDevices();
    result.fold(
      (failure) => emit(DevicesError(failure.message)),
      (devices) => emit(DevicesLoaded(devices)),
    );
  }

  Future<void> _onLoadDevice(
    LoadDevice event,
    Emitter<DevicesState> emit,
  ) async {
    emit(const DevicesLoading());
    final result = await _repository.getDevice(event.deviceId);
    result.fold(
      (failure) => emit(DevicesError(failure.message)),
      (device) => emit(DeviceDetailLoaded(device)),
    );
  }

  Future<void> _onCreateDevice(
    CreateDevice event,
    Emitter<DevicesState> emit,
  ) async {
    emit(const DevicesLoading());
    final result = await _repository.createDevice(name: event.name);
    result.fold(
      (failure) => emit(DevicesError(failure.message)),
      (_) => add(const LoadDevices()),
    );
  }

  Future<void> _onDeleteDevice(
    DeleteDevice event,
    Emitter<DevicesState> emit,
  ) async {
    emit(const DevicesLoading());
    final result = await _repository.deleteDevice(event.deviceId);
    result.fold(
      (failure) => emit(DevicesError(failure.message)),
      (_) => add(const LoadDevices()),
    );
  }

  Future<void> _onUpdateSettings(
    UpdateSettings event,
    Emitter<DevicesState> emit,
  ) async {
    emit(const DevicesLoading());
    final result = await _repository.updateSettings(event.deviceId, event.settings);
    result.fold(
      (failure) => emit(DevicesError(failure.message)),
      (device) => emit(DeviceDetailLoaded(device)),
    );
  }

}
