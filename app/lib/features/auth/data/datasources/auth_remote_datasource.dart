import '../../../../core/network/api_client.dart';
import '../models/user_model.dart';

class AuthRemoteDatasource {
  final ApiClient _apiClient;

  AuthRemoteDatasource(this._apiClient);

  /// Returns { accessToken, refreshToken, user } from unwrapped response.
  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final data = await _apiClient.post(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    return AuthResponse.fromJson(data as Map<String, dynamic>);
  }

  Future<AuthResponse> register({
    required String email,
    required String password,
    required String name,
  }) async {
    final data = await _apiClient.post(
      '/auth/register',
      data: {'email': email, 'password': password, 'name': name},
    );
    return AuthResponse.fromJson(data as Map<String, dynamic>);
  }
}

/// Parsed auth response after envelope unwrapping.
class AuthResponse {
  final String accessToken;
  final String refreshToken;
  final UserModel user;

  const AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}
