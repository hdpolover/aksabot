import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/ota_status.dart';
import '../../domain/repositories/firmware_repository.dart';
import 'firmware_event.dart';
import 'firmware_state.dart';

class FirmwareBloc extends Bloc<FirmwareEvent, FirmwareState> {
  final FirmwareRepository _repo;
  Timer? _pollTimer;

  FirmwareBloc(this._repo) : super(const FirmwareInitial()) {
    on<FirmwarePageOpened>(_onPageOpened);
    on<FirmwareOtaTriggered>(_onOtaTriggered);
    on<FirmwareOtaStatusPolled>(_onStatusPolled);
  }

  Future<void> _onPageOpened(
    FirmwarePageOpened event,
    Emitter<FirmwareState> emit,
  ) async {
    emit(const FirmwareLoading());

    final releaseResult = await _repo.getLatestRelease();
    final statusResult = await _repo.getOtaStatus(event.deviceId);

    final release = releaseResult.fold((_) => null, (r) => r);
    final status = statusResult.fold((_) => OtaStatus.idle, (s) => s);

    emit(FirmwareLoaded(latest: release, otaStatus: status));

    // If already in progress from a previous session, start polling
    if (status.isActive) {
      _startPolling(event.deviceId);
    }
  }

  Future<void> _onOtaTriggered(
    FirmwareOtaTriggered event,
    Emitter<FirmwareState> emit,
  ) async {
    emit(const FirmwareTriggerInProgress());

    final result = await _repo.triggerOta(event.deviceId, releaseId: event.releaseId);

    await result.fold(
      (failure) async => emit(FirmwareError(failure.message)),
      (_) async {
        final statusResult = await _repo.getOtaStatus(event.deviceId);
        final status = statusResult.fold((_) => OtaStatus.idle, (s) => s);
        final releaseResult = await _repo.getLatestRelease();
        final release = releaseResult.fold((_) => null, (r) => r);
        emit(FirmwareLoaded(latest: release, otaStatus: status));
        _startPolling(event.deviceId);
      },
    );
  }

  Future<void> _onStatusPolled(
    FirmwareOtaStatusPolled event,
    Emitter<FirmwareState> emit,
  ) async {
    final current = state;
    if (current is! FirmwareLoaded) return;

    final result = await _repo.getOtaStatus(event.deviceId);
    final status = result.fold((_) => current.otaStatus, (s) => s);

    emit(current.copyWith(otaStatus: status));

    // Stop polling once the update is no longer active
    if (!status.isActive) {
      _stopPolling();
    }
  }

  void _startPolling(String deviceId) {
    _stopPolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      add(FirmwareOtaStatusPolled(deviceId));
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  Future<void> close() {
    _stopPolling();
    return super.close();
  }
}
