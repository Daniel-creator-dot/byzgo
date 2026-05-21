import 'package:dio/dio.dart';

import 'env.dart';

typedef UnauthorizedHandler = void Function();

/// REST client for the existing Express API (`backend/server.ts`).
class ApiClient {
  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: true,
        maxRedirects: 5,
        headers: {'Content-Type': 'application/json'},
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (err, handler) {
          final status = err.response?.statusCode;
          if (status == 401 || status == 403) {
            onUnauthorized?.call();
          }
          handler.next(err);
        },
      ),
    );
  }

  late final Dio _dio;
  UnauthorizedHandler? onUnauthorized;

  Dio get dio => _dio;

  void setToken(String? token) {
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  static String messageFromDio(DioException err, [String fallback = 'Something went wrong']) {
    final status = err.response?.statusCode;
    if (status == 413) {
      return 'Photo or request is too large. Use a smaller image, or save without changing the photo.';
    }
    final data = err.response?.data;
    if (data is Map) {
      final m = data['message'] ?? data['error'];
      if (m != null) return m.toString();
    }
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout) {
      return 'Cannot reach the server at ${Env.apiBaseUrl}. '
          'Check your internet connection. For local dev on emulator use '
          'API_URL=http://10.0.2.2:3000 with npm run backend.';
    }
    return err.message ?? fallback;
  }
}
