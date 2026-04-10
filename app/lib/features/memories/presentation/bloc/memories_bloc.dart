import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/memory_entity.dart';
import '../../domain/repositories/memories_repository.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

abstract class MemoriesEvent extends Equatable {
  const MemoriesEvent();

  @override
  List<Object?> get props => [];
}

class LoadMemories extends MemoriesEvent {
  final String deviceId;
  final String? category;
  const LoadMemories(this.deviceId, {this.category});

  @override
  List<Object?> get props => [deviceId, category];
}

class DeleteMemory extends MemoriesEvent {
  final String memoryId;
  const DeleteMemory(this.memoryId);

  @override
  List<Object?> get props => [memoryId];
}

class UpdateMemory extends MemoriesEvent {
  final String memoryId;
  final String? fact;
  final String? category;
  const UpdateMemory(this.memoryId, {this.fact, this.category});

  @override
  List<Object?> get props => [memoryId, fact, category];
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

abstract class MemoriesState extends Equatable {
  const MemoriesState();

  @override
  List<Object?> get props => [];
}

class MemoriesInitial extends MemoriesState {
  const MemoriesInitial();
}

class MemoriesLoading extends MemoriesState {
  const MemoriesLoading();
}

class MemoriesLoaded extends MemoriesState {
  final List<Memory> memories;
  final String? selectedCategory;

  const MemoriesLoaded(this.memories, {this.selectedCategory});

  @override
  List<Object?> get props => [memories, selectedCategory];
}

class MemoriesError extends MemoriesState {
  final String message;
  const MemoriesError(this.message);

  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// BLoC
// ---------------------------------------------------------------------------

class MemoriesBloc extends Bloc<MemoriesEvent, MemoriesState> {
  final MemoriesRepository _repository;
  String? _currentDeviceId;

  MemoriesBloc(this._repository) : super(const MemoriesInitial()) {
    on<LoadMemories>(_onLoadMemories);
    on<DeleteMemory>(_onDeleteMemory);
    on<UpdateMemory>(_onUpdateMemory);
  }

  Future<void> _onLoadMemories(
    LoadMemories event,
    Emitter<MemoriesState> emit,
  ) async {
    _currentDeviceId = event.deviceId;
    emit(const MemoriesLoading());
    final result = await _repository.getMemories(
      event.deviceId,
      category: event.category,
    );
    result.fold(
      (failure) => emit(MemoriesError(failure.message)),
      (memories) => emit(MemoriesLoaded(memories, selectedCategory: event.category)),
    );
  }

  Future<void> _onDeleteMemory(
    DeleteMemory event,
    Emitter<MemoriesState> emit,
  ) async {
    final current = state;
    if (current is! MemoriesLoaded) return;

    final result = await _repository.deleteMemory(event.memoryId);
    result.fold(
      (_) => null,
      (_) {
        final updated = current.memories.where((m) => m.id != event.memoryId).toList();
        emit(MemoriesLoaded(updated, selectedCategory: current.selectedCategory));
      },
    );
  }

  Future<void> _onUpdateMemory(
    UpdateMemory event,
    Emitter<MemoriesState> emit,
  ) async {
    if (_currentDeviceId == null) return;
    final current = state;
    if (current is! MemoriesLoaded) return;

    final result = await _repository.updateMemory(
      event.memoryId,
      fact: event.fact,
      category: event.category,
    );
    result.fold(
      (_) => null,
      (_) => add(LoadMemories(_currentDeviceId!, category: current.selectedCategory)),
    );
  }
}
