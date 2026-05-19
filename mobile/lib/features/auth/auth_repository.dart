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

  Future<void> sendSignupOtp({
    required String phone,
    required String email,
  }) async {
    await _api.dio.post<Map<String, dynamic>>(
      '/api/auth/send-signup-otp',
      data: {'phone': phone.trim(), 'email': email.trim()},
    );
  }

  Future<void> sendForgotPasswordOtp(String phone) async {
    await _api.dio.post<Map<String, dynamic>>(
      '/api/auth/send-forgot-otp',
      data: {'phone': phone.trim()},
    );
  }

  Future<void> resendOtp({
    required String phone,
    required String purpose,
    String? email,
  }) async {
    await _api.dio.post<Map<String, dynamic>>(
      '/api/auth/resend-otp',
      data: {
        'phone': phone.trim(),
        'purpose': purpose,
        if (email != null) 'email': email.trim(),
      },
    );
  }

  Future<void> verifyOtp({
    required String phone,
    required String otp,
    required String purpose,
  }) async {
    await _api.dio.post<Map<String, dynamic>>(
      '/api/auth/verify-otp',
      data: {
        'phone': phone.trim(),
        'otp': otp.trim(),
        'purpose': purpose,
      },
    );
  }

  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
    required AppRole role,
    String? phone,
    String? otp,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/auth/register',
      data: {
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'role': role.name,
        if (phone != null && phone.isNotEmpty) 'phone': phone.trim(),
        if (otp != null) 'otp': otp.trim(),
      },
    );
    return _parseAuthResponse(res.data);
  }

  Future<void> resetPasswordWithOtp({
    required String phone,
    required String otp,
    required String newPassword,
  }) async {
    await _api.dio.post<Map<String, dynamic>>(
      '/api/auth/reset-password-otp',
      data: {
        'phone': phone.trim(),
        'otp': otp.trim(),
        'newPassword': newPassword,
      },
    );
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
    String? address,
    double? lat,
    double? lng,
    String? email,
  }) async {
    final res = await _api.dio.patch<Map<String, dynamic>>(
      '/api/auth/profile',
      data: {
        if (phone != null) 'phone': phone,
        if (region != null) 'region': region,
        if (address != null) 'address': address,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (email != null) 'email': email,
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
