import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

/// Lightweight logger that only outputs in debug mode.
///
/// Uses `dart:developer` log which integrates with DevTools,
/// unlike `print()` which leaks into release builds.
abstract final class AppLogger {
  static void debug(String tag, String message) {
    if (kDebugMode) {
      dev.log(message, name: tag);
    }
  }

  static void info(String tag, String message) {
    if (kDebugMode) {
      dev.log(message, name: tag, level: 800);
    }
  }

  static void warning(String tag, String message) {
    if (kDebugMode) {
      dev.log(message, name: tag, level: 900);
    }
  }

  static void error(String tag, String message, [Object? error]) {
    if (kDebugMode) {
      dev.log(message, name: tag, level: 1000, error: error);
    }
  }
}
