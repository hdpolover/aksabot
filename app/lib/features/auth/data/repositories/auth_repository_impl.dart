import 'package:dartz/dartz.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../../core/constants/storage_keys.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';

class AuthRepositoryImpl implements AuthRepository {
  static const _tag = 'AuthRepo';

  final AuthRemoteDatasource _remoteDatasource;
  final FlutterSecureStorage _storage;

  AuthRepositoryImpl(this._remoteDatasource, this._storage);

  @override
  Future<Either<Failure, User>> login({
    required String email,
    required String password,
  }) async {
    try {
      AppLogger.debug(_tag, 'login attempt: $email');
      final response = await _remoteDatasource.login(
        email: email,
        password: password,
      );
      AppLogger.debug(_tag, 'login success, persisting tokens');
      await _persistTokens(response.accessToken, response.refreshToken);
      return Right(response.user);
    } on AuthException catch (e) {
      AppLogger.warning(_tag, 'AuthException: ${e.message}');
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      AppLogger.error(_tag, 'ServerException: ${e.statusCode} ${e.message}');
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    } catch (e) {
      AppLogger.error(_tag, 'Unexpected error', e);
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, User>> register({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final response = await _remoteDatasource.register(
        email: email,
        password: password,
        name: name,
      );
      await _persistTokens(response.accessToken, response.refreshToken);
      return Right(response.user);
    } on AuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> logout() async {
    try {
      await _storage.delete(key: StorageKeys.accessToken);
      await _storage.delete(key: StorageKeys.refreshToken);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: StorageKeys.accessToken);
    return token != null;
  }

  @override
  Future<String?> getToken() async {
    return _storage.read(key: StorageKeys.accessToken);
  }

  @override
  Future<Either<Failure, User>> getCurrentUser() async {
    try {
      final user = await _remoteDatasource.getCurrentUser();
      return Right(user);
    } on AuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      if (e.statusCode == 401) {
        await _storage.delete(key: StorageKeys.accessToken);
        await _storage.delete(key: StorageKeys.refreshToken);
      }
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> forgotPassword({required String email}) async {
    try {
      await _remoteDatasource.forgotPassword(email: email);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      await _remoteDatasource.resetPassword(
        email: email,
        code: code,
        newPassword: newPassword,
      );
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, statusCode: e.statusCode));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<void> _persistTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: StorageKeys.accessToken, value: accessToken);
    await _storage.write(key: StorageKeys.refreshToken, value: refreshToken);
  }
}
