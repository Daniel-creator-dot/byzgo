import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/api_client.dart';
import '../../core/env.dart';
import '../../models/auth_user.dart';
import '../../models/role.dart';

class AuthResult {
  const AuthResult({required this.user, required this.token});
  final AuthUser user;
  final String token;
}

class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: {'email': email.trim(), 'password': password},
    );
    return _parseAuthResponse(res.data);
  }

  Future<AuthResult> signInWithGoogle({AppRole role = AppRole.customer}) async {
    if (!Env.isGoogleSignInEnabled) {
      throw Exception(
        'Google Sign-In is not configured. Set GOOGLE_WEB_CLIENT_ID and run flutterfire configure.',
      );
    }

    final googleSignIn = GoogleSignIn(
      serverClientId: Env.googleWebClientId,
    );
    final account = await googleSignIn.signIn();
    if (account == null) {
      throw Exception('Google sign-in cancelled');
    }
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw Exception('No Google ID token — check GOOGLE_WEB_CLIENT_ID');
    }

    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/auth/google',
      data: {'credential': idToken, 'role': role.name},
    );
    return _parseAuthResponse(res.data);
  }

  Future<AuthResult> updateProfile({
    String? phone,
    String? region,
  }) async {
    final res = await _api.dio.patch<Map<String, dynamic>>(
      '/api/auth/profile',
      data: {
        if (phone != null) 'phone': phone,
        if (region != null) 'region': region,
      },
    );
    return _parseAuthResponse(res.data);
  }

  Future<AuthResult> updateStatus(String status) async {
    final res = await _api.dio.patch<Map<String, dynamic>>(
      '/api/auth/status',
      data: {'status': status},
    );
    return _parseAuthResponse(res.data);
  }

  AuthResult _parseAuthResponse(Map<String, dynamic>? data) {
    if (data == null) throw Exception('Empty auth response');
    final token = data['token']?.toString();
    final userJson = data['user'];
    if (token == null || userJson is! Map) {
      throw Exception('Invalid auth response');
    }
    return AuthResult(
      token: token,
      user: AuthUser.fromJson(Map<String, dynamic>.from(userJson)),
    );
  }

  static String errorMessage(Object err) {
    if (err is DioException) {
      return ApiClient.messageFromDio(err, 'Authentication failed');
    }
    if (err is Exception) return err.toString().replaceFirst('Exception: ', '');
    return err.toString();
  }
}
