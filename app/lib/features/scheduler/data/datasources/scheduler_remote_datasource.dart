import '../../../../core/network/api_client.dart';
import '../models/reminder_config_model.dart';
import '../models/pomodoro_model.dart';

class SchedulerRemoteDatasource {
  final ApiClient _client;

  SchedulerRemoteDatasource(this._client);

  Future<ReminderConfigModel> getReminderConfig(String deviceId) async {
    final data = await _client.get('/devices/$deviceId/reminders');
    return ReminderConfigModel.fromJson(data as Map<String, dynamic>);
  }

  Future<ReminderConfigModel> updateReminderConfig(
    String deviceId,
    Map<String, dynamic> config,
  ) async {
    final data = await _client.put(
      '/devices/$deviceId/reminders',
      data: config,
    );
    return ReminderConfigModel.fromJson(data as Map<String, dynamic>);
  }

  Future<PomodoroModel> startPomodoro(String deviceId) async {
    final data = await _client.post('/devices/$deviceId/pomodoro/start');
    return PomodoroModel.fromJson(data as Map<String, dynamic>);
  }

  Future<void> stopPomodoro(String deviceId) async {
    await _client.post('/devices/$deviceId/pomodoro/stop');
  }

  Future<PomodoroModel> getPomodoroStatus(String deviceId) async {
    final data = await _client.get('/devices/$deviceId/pomodoro');
    return PomodoroModel.fromJson(data as Map<String, dynamic>);
  }
}
