import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/api.dart';
import '../error/exceptions.dart';

class ApiClient {
  late final Dio dio;
  final FlutterSecureStorage _storage;

  ApiClient(this._storage) {
    dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
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
    final token = await _storage.read(key: 'access_token');
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    if (error.response?.statusCode == 401) {
      // Try refresh
      final refreshed = await _tryRefresh();
      if (refreshed) {
        // Retry original request
        final opts = error.requestOptions;
        final token = await _storage.read(key: 'access_token');
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
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null) return false;

    try {
      final response = await Dio(BaseOptions(
        baseUrl: ApiConstants.baseUrl,
      )).post('/auth/refresh', data: {'refreshToken': refreshToken});

      final data = response.data['data'];
      await _storage.write(key: 'access_token', value: data['accessToken']);
      await _storage.write(key: 'refresh_token', value: data['refreshToken']);
      return true;
    } catch (_) {
      // Refresh failed — clear tokens
      await _storage.delete(key: 'access_token');
      await _storage.delete(key: 'refresh_token');
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
      final response = await dio.post(path, data: data);
      return unwrap(response);
    } on DioException catch (e) {
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
    final message = e.response?.data?['message'] ?? e.message ?? 'Unknown error';
    return ServerException(
      message is List ? message.join(', ') : message.toString(),
      statusCode: e.response?.statusCode,
    );
  }
}
