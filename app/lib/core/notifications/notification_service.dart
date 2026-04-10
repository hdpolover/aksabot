import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages local notifications for reminders, pomodoro, and device alerts.
///
/// Push notifications via FCM will be added once the backend supports it.
class NotificationService {
  static const _prefEnabled = 'notifications_enabled';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initialize the notification plugin with platform-specific settings.
  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);
    _initialized = true;
  }

  /// Request notification permissions (iOS requires explicit permission).
  Future<bool> requestPermission() async {
    // iOS
    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (iosPlugin != null) {
      final granted = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    // Android 13+ (API 33)
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      return granted ?? false;
    }

    return true;
  }

  /// Show a notification for a reminder (stand up, hydration, etc.).
  Future<void> showReminder({
    required int id,
    required String title,
    required String body,
  }) async {
    await _ensureInitialized();

    const androidDetails = AndroidNotificationDetails(
      'reminders',
      'Health Reminders',
      channelDescription: 'Reminders for stand up, hydration, eye break, etc.',
      importance: Importance.high,
      priority: Priority.defaultPriority,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.show(id, title, body, details);
  }

  /// Show a notification for pomodoro phase transitions.
  Future<void> showPomodoro({
    required int id,
    required String title,
    required String body,
  }) async {
    await _ensureInitialized();

    const androidDetails = AndroidNotificationDetails(
      'pomodoro',
      'Pomodoro Timer',
      channelDescription: 'Notifications for pomodoro focus/break transitions.',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.show(id, title, body, details);
  }

  /// Show a notification for device connection state changes.
  Future<void> showDeviceAlert({
    required int id,
    required String title,
    required String body,
  }) async {
    await _ensureInitialized();

    const androidDetails = AndroidNotificationDetails(
      'device_alerts',
      'Device Alerts',
      channelDescription: 'Alerts when your Aksabot goes online or offline.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.show(id, title, body, details);
  }

  /// Cancel a specific notification by id.
  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  /// Cancel all notifications.
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  // ── Persisted Settings ────────────────────────────────────────

  Future<bool> loadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabled) ?? false;
  }

  Future<void> saveEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, enabled);
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await init();
  }
}
