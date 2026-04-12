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

class ScanMemories extends MemoriesEvent {
  final String deviceId;
  const ScanMemories(this.deviceId);

  @override
  List<Object?> get props => [deviceId];
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
  final bool scanning;
  final int? lastScanExtracted;

  const MemoriesLoaded(
    this.memories, {
    this.selectedCategory,
    this.scanning = false,
    this.lastScanExtracted,
  });

  MemoriesLoaded copyWith({
    List<Memory>? memories,
    String? selectedCategory,
    bool? scanning,
    int? lastScanExtracted,
  }) {
    return MemoriesLoaded(
      memories ?? this.memories,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      scanning: scanning ?? this.scanning,
      lastScanExtracted: lastScanExtracted ?? this.lastScanExtracted,
    );
  }

  @override
  List<Object?> get props => [memories, selectedCategory, scanning, lastScanExtracted];
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
    on<ScanMemories>(_onScanMemories);
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

  Future<void> _onScanMemories(
    ScanMemories event,
    Emitter<MemoriesState> emit,
  ) async {
    final current = state;
    if (current is! MemoriesLoaded) return;

    emit(current.copyWith(scanning: true, lastScanExtracted: null));

    final scanResult = await _repository.scanMemories(event.deviceId);

    int? extracted;
    scanResult.fold(
      (_) => null,
      (data) => extracted = data['extracted'] as int? ?? 0,
    );

    // Reload list inline so newly extracted memories appear without racing
    final memoriesResult = await _repository.getMemories(
      event.deviceId,
      category: current.selectedCategory,
    );

    memoriesResult.fold(
      (failure) => emit(MemoriesError(failure.message)),
      (memories) => emit(MemoriesLoaded(
        memories,
        selectedCategory: current.selectedCategory,
        scanning: false,
        lastScanExtracted: extracted,
      )),
    );
  }
}
