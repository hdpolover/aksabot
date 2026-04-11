import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/api.dart';
import '../constants/app_constants.dart';
import '../constants/storage_keys.dart';
import '../error/exceptions.dart';
import '../utils/logger.dart';

class ApiClient {
  static const _tag = 'ApiClient';

  late final Dio dio;
  final FlutterSecureStorage _storage;

  ApiClient(this._storage) {
    dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: AppConstants.connectTimeout,
      receiveTimeout: AppConstants.receiveTimeout,
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onError: _onError,
    ));
  }

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storage.read(key: StorageKeys.accessToken);
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
      AppLogger.debug(_tag, '${options.method} ${options.baseUrl}${options.path} [token: ${token.substring(0, 20)}...]');
    } else {
      AppLogger.debug(_tag, '${options.method} ${options.baseUrl}${options.path} [NO TOKEN]');
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    if (error.response?.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        final opts = error.requestOptions;
        final token = await _storage.read(key: StorageKeys.accessToken);
        opts.headers['Authorization'] = 'Bearer $token';
        try {
          final response = await dio.fetch(opts);
          return handler.resolve(response);
        } on DioException catch (e) {
          return handler.next(e);
        }
      }
    }
    handler.next(error);
  }

  Future<bool> _tryRefresh() async {
    final refreshToken = await _storage.read(key: StorageKeys.refreshToken);
    if (refreshToken == null) return false;

    try {
      final response = await Dio(BaseOptions(
        baseUrl: ApiConstants.baseUrl,
      )).post('/auth/refresh', data: {'refreshToken': refreshToken});

      final data = response.data['data'];
      await _storage.write(key: StorageKeys.accessToken, value: data['accessToken']);
      await _storage.write(key: StorageKeys.refreshToken, value: data['refreshToken']);
      return true;
    } catch (_) {
      await _storage.delete(key: StorageKeys.accessToken);
      await _storage.delete(key: StorageKeys.refreshToken);
      return false;
    }
  }

  /// Unwrap the backend response envelope { data, meta }
  dynamic unwrap(Response response) {
    final body = response.data;
    if (body is Map && body.containsKey('data')) {
      return body['data'];
    }
    return body;
  }

  /// GET with unwrap
  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      final response = await dio.get(path, queryParameters: queryParameters);
      return unwrap(response);
    } on DioException catch (e) {
      throw _mapException(e);
    }
  }

  /// POST with unwrap
  Future<dynamic> post(String path, {dynamic data}) async {
    try {
      AppLogger.debug(_tag, 'POST ${dio.options.baseUrl}$path');
      final response = await dio.post(path, data: data);
      AppLogger.debug(_tag, 'POST $path → ${response.statusCode}');
      return unwrap(response);
    } on DioException catch (e) {
      AppLogger.error(_tag, 'POST $path FAILED: ${e.type} — ${e.message}');
      if (e.response != null) {
        AppLogger.error(
          _tag,
          'Response: ${e.response?.statusCode} ${e.response?.data}',
        );
      }
      throw _mapException(e);
    }
  }

  /// PATCH with unwrap
  Future<dynamic> patch(String path, {dynamic data}) async {
    try {
      final response = await dio.patch(path, data: data);
      return unwrap(response);
    } on DioException catch (e) {
      throw _mapException(e);
    }
  }

  /// PUT with unwrap
  Future<dynamic> put(String path, {dynamic data}) async {
    try {
      final response = await dio.put(path, data: data);
      return unwrap(response);
    } on DioException catch (e) {
      throw _mapException(e);
    }
  }

  /// DELETE
  Future<void> delete(String path) async {
    try {
      await dio.delete(path);
    } on DioException catch (e) {
      throw _mapException(e);
    }
  }

  ServerException _mapException(DioException e) {
    final data = e.response?.data;
    final statusCode = e.response?.statusCode;

    // Extract clean message from NestJS error response
    String message;
    if (data is Map) {
      final msg = data['message'];
      if (msg is List) {
        message = msg.join(', ');
      } else if (msg is String) {
        message = msg;
      } else {
        message = data['error'] as String? ?? 'Request failed';
      }
    } else if (e.type == DioExceptionType.connectionTimeout ||
               e.type == DioExceptionType.receiveTimeout) {
      message = 'Connection timed out';
    } else if (e.type == DioExceptionType.connectionError) {
      message = 'Could not connect to server';
    } else {
      message = statusCode != null
          ? 'Request failed ($statusCode)'
          : 'Network error';
    }

    return ServerException(message, statusCode: statusCode);
  }
}
