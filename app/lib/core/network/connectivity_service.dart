import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Wraps connectivity_plus to provide a simple stream of online/offline state.
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  StreamController<bool>? _controller;

  /// Stream that emits `true` when online, `false` when offline.
  Stream<bool> get onConnectivityChanged {
    _controller ??= StreamController<bool>.broadcast();

    _connectivity.onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      _controller!.add(isOnline);
    });

    return _controller!.stream;
  }

  /// Check current connectivity status.
  Future<bool> get isOnline async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  void dispose() {
    _controller?.close();
    _controller = null;
  }
}
