import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/reminder_config_entity.dart';
import '../../domain/entities/pomodoro_entity.dart';
import '../../domain/repositories/scheduler_repository.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

abstract class SchedulerEvent extends Equatable {
  const SchedulerEvent();

  @override
  List<Object?> get props => [];
}

// Reminders
class LoadReminderConfig extends SchedulerEvent {
  final String deviceId;
  const LoadReminderConfig(this.deviceId);

  @override
  List<Object?> get props => [deviceId];
}

class UpdateReminderConfig extends SchedulerEvent {
  final String deviceId;
  final Map<String, dynamic> config;
  const UpdateReminderConfig(this.deviceId, this.config);

  @override
  List<Object?> get props => [deviceId, config];
}

// Pomodoro
class LoadPomodoroStatus extends SchedulerEvent {
  final String deviceId;
  const LoadPomodoroStatus(this.deviceId);

  @override
  List<Object?> get props => [deviceId];
}

class StartPomodoro extends SchedulerEvent {
  final String deviceId;
  const StartPomodoro(this.deviceId);

  @override
  List<Object?> get props => [deviceId];
}

class StopPomodoro extends SchedulerEvent {
  final String deviceId;
  const StopPomodoro(this.deviceId);

  @override
  List<Object?> get props => [deviceId];
}

// Focus mode
class StartFocusMode extends SchedulerEvent {
  final String deviceId;
  final int? durationMinutes;
  const StartFocusMode(this.deviceId, {this.durationMinutes});

  @override
  List<Object?> get props => [deviceId, durationMinutes];
}

class StopFocusMode extends SchedulerEvent {
  final String deviceId;
  const StopFocusMode(this.deviceId);

  @override
  List<Object?> get props => [deviceId];
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

abstract class SchedulerState extends Equatable {
  const SchedulerState();

  @override
  List<Object?> get props => [];
}

class SchedulerInitial extends SchedulerState {
  const SchedulerInitial();
}

class SchedulerLoading extends SchedulerState {
  const SchedulerLoading();
}

class ReminderConfigLoaded extends SchedulerState {
  final ReminderConfig config;
  final bool isSaving;

  const ReminderConfigLoaded(this.config, {this.isSaving = false});

  @override
  List<Object?> get props => [config, isSaving];
}

class PomodoroStatusLoaded extends SchedulerState {
  final PomodoroStatus status;
  final bool isActing;

  const PomodoroStatusLoaded(this.status, {this.isActing = false});

  @override
  List<Object?> get props => [status, isActing];
}

class FocusModeActive extends SchedulerState {
  const FocusModeActive();
}

class FocusModeInactive extends SchedulerState {
  const FocusModeInactive();
}

class SchedulerError extends SchedulerState {
  final String message;
  const SchedulerError(this.message);

  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// BLoC
// ---------------------------------------------------------------------------

class SchedulerBloc extends Bloc<SchedulerEvent, SchedulerState> {
  final SchedulerRepository _repository;

  SchedulerBloc(this._repository) : super(const SchedulerInitial()) {
    on<LoadReminderConfig>(_onLoadReminderConfig);
    on<UpdateReminderConfig>(_onUpdateReminderConfig);
    on<LoadPomodoroStatus>(_onLoadPomodoroStatus);
    on<StartPomodoro>(_onStartPomodoro);
    on<StopPomodoro>(_onStopPomodoro);
    on<StartFocusMode>(_onStartFocusMode);
    on<StopFocusMode>(_onStopFocusMode);
  }

  Future<void> _onLoadReminderConfig(
    LoadReminderConfig event,
    Emitter<SchedulerState> emit,
  ) async {
    emit(const SchedulerLoading());
    final result = await _repository.getReminderConfig(event.deviceId);
    result.fold(
      (failure) => emit(SchedulerError(failure.message)),
      (config) => emit(ReminderConfigLoaded(config)),
    );
  }

  Future<void> _onUpdateReminderConfig(
    UpdateReminderConfig event,
    Emitter<SchedulerState> emit,
  ) async {
    final current = state;
    if (current is ReminderConfigLoaded) {
      emit(ReminderConfigLoaded(current.config, isSaving: true));
    }
    final result = await _repository.updateReminderConfig(
      event.deviceId,
      event.config,
    );
    result.fold(
      (failure) => emit(SchedulerError(failure.message)),
      (config) => emit(ReminderConfigLoaded(config)),
    );
  }

  Future<void> _onLoadPomodoroStatus(
    LoadPomodoroStatus event,
    Emitter<SchedulerState> emit,
  ) async {
    emit(const SchedulerLoading());
    final result = await _repository.getPomodoroStatus(event.deviceId);
    result.fold(
      (failure) => emit(SchedulerError(failure.message)),
      (status) => emit(PomodoroStatusLoaded(status)),
    );
  }

  Future<void> _onStartPomodoro(
    StartPomodoro event,
    Emitter<SchedulerState> emit,
  ) async {
    final current = state;
    if (current is PomodoroStatusLoaded) {
      emit(PomodoroStatusLoaded(current.status, isActing: true));
    }
    final result = await _repository.startPomodoro(event.deviceId);
    result.fold(
      (failure) => emit(SchedulerError(failure.message)),
      (status) => emit(PomodoroStatusLoaded(status)),
    );
  }

  Future<void> _onStopPomodoro(
    StopPomodoro event,
    Emitter<SchedulerState> emit,
  ) async {
    final current = state;
    if (current is PomodoroStatusLoaded) {
      emit(PomodoroStatusLoaded(current.status, isActing: true));
    }
    final result = await _repository.stopPomodoro(event.deviceId);
    result.fold(
      (failure) => emit(SchedulerError(failure.message)),
      (_) => emit(const PomodoroStatusLoaded(PomodoroStatus(active: false))),
    );
  }

  Future<void> _onStartFocusMode(
    StartFocusMode event,
    Emitter<SchedulerState> emit,
  ) async {
    emit(const SchedulerLoading());
    final result = await _repository.startFocusMode(
      event.deviceId,
      durationMinutes: event.durationMinutes,
    );
    result.fold(
      (failure) => emit(SchedulerError(failure.message)),
      (_) => emit(const FocusModeActive()),
    );
  }

  Future<void> _onStopFocusMode(
    StopFocusMode event,
    Emitter<SchedulerState> emit,
  ) async {
    emit(const SchedulerLoading());
    final result = await _repository.stopFocusMode(event.deviceId);
    result.fold(
      (failure) => emit(SchedulerError(failure.message)),
      (_) => emit(const FocusModeInactive()),
    );
  }
}
