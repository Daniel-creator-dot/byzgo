import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/api_client.dart';
import '../../core/env.dart';
import '../../core/oauth_config.dart';
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

  /// Sign in with Ghana phone (024…) or email + password.
  Future<AuthResult> login({
    required String login,
    required String password,
  }) async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: {'login': login.trim(), 'password': password},
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

  /// Reset password using registered phone + email (no SMS).
  Future<void> resetPassword({
    required String phone,
    required String email,
    required String newPassword,
  }) async {
    await _api.dio.post<Map<String, dynamic>>(
      '/api/auth/reset-password',
      data: {
        'phone': phone.trim(),
        'email': email.trim(),
        'newPassword': newPassword,
      },
    );
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

    // Sideload APKs: native Google Sign-In often fails with certificate error 10; use web OAuth instead.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return _signInWithGoogleWeb(role);
    }
    return _signInWithGoogleNative(role);
  }

  /// Browser-based Google Sign-In (same as bytzgo.net web) — no APK certificate check.
  Future<AuthResult> _signInWithGoogleWeb(AppRole role) async {
    final url = '${Env.apiBaseUrl}/auth/google-mobile?role=${role.name}';
    try {
      final result = await FlutterWebAuth2.authenticate(
        url: url,
        callbackUrlScheme: 'bytzgo',
      );
      final uri = Uri.parse(result);
      final err = uri.queryParameters['error'];
      if (err != null && err.isNotEmpty) {
        throw Exception(err);
      }
      final token = uri.queryParameters['token'];
      if (token == null || token.isEmpty) {
        throw Exception('Google sign-in cancelled');
      }
      final res = await _api.dio.get<Map<String, dynamic>>(
        '/api/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return _parseAuthResponse(res.data);
    } on DioException catch (e) {
      throw Exception(AuthRepository.errorMessage(e));
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') {
        throw Exception('Google sign-in cancelled');
      }
      rethrow;
    }
  }

  Future<AuthResult> _signInWithGoogleNative(AppRole role) async {
    final googleSignIn = GoogleSignIn(
      clientId: defaultTargetPlatform == TargetPlatform.iOS ? kGoogleIosClientId : null,
      serverClientId: Env.googleWebClientId.trim().isNotEmpty
          ? Env.googleWebClientId
          : kGoogleWebClientId,
      scopes: const ['email', 'profile', 'openid'],
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

    try {
      final res = await _api.dio.post<Map<String, dynamic>>(
        '/api/auth/google',
        data: {'credential': idToken, 'role': role.name},
      );
      return _parseAuthResponse(res.data);
    } on DioException catch (e) {
      throw Exception(AuthRepository.errorMessage(e));
    }
  }

  Future<AuthResult> signInWithApple({AppRole role = AppRole.customer}) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      throw Exception('Sign in with Apple is only available on iOS.');
    }

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final idToken = credential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('No Apple identity token');
      }

      final given = credential.givenName?.trim();
      final family = credential.familyName?.trim();
      final fullName = [given, family].whereType<String>().where((s) => s.isNotEmpty).join(' ');

      final res = await _api.dio.post<Map<String, dynamic>>(
        '/api/auth/apple',
        data: {
          'credential': idToken,
          'role': role.name,
          if (credential.email != null && credential.email!.isNotEmpty)
            'email': credential.email,
          if (fullName.isNotEmpty) 'name': fullName,
        },
      );
      return _parseAuthResponse(res.data);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw Exception('Apple sign-in cancelled');
      }
      throw Exception('Apple sign-in failed');
    } on DioException catch (e) {
      throw Exception(AuthRepository.errorMessage(e));
    }
  }

  Future<void> deleteAccount() async {
    await _api.dio.delete<Map<String, dynamic>>('/api/auth/account');
  }

  Future<String> uploadProfileImage(String filePath) async {
    return _uploadImage(filePath, folder: 'avatars', filename: 'profile.jpg');
  }

  Future<String> uploadCoverImage(String filePath) async {
    return _uploadImage(filePath, folder: 'covers', filename: 'cover.jpg');
  }

  Future<String> _uploadImage(
    String filePath, {
    required String folder,
    required String filename,
  }) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(filePath, filename: filename),
      'folder': folder,
    });
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/upload',
      data: formData,
    );
    final url = res.data?['url']?.toString();
    if (url == null || url.isEmpty) {
      throw Exception('Upload failed — no image URL returned');
    }
    return url;
  }

  Future<AuthResult> refreshSession() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/auth/me');
    return _parseAuthResponse(res.data);
  }

  Future<AuthResult> updateProfile({
    String? phone,
    String? region,
    String? address,
    double? lat,
    double? lng,
    String? email,
    String? shopCategory,
    String? avatarUrl,
    String? coverImage,
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
        if (shopCategory != null) 'shop_category': shopCategory,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (coverImage != null) 'cover_image': coverImage,
      },
    );
    return _parseAuthResponse(res.data);
  }

  Future<AuthUser> updateRiderVehicleType(String vehicleType) async {
    final res = await _api.dio.patch<Map<String, dynamic>>(
      '/api/rider/vehicle-type',
      data: {'vehicle_type': vehicleType},
    );
    final userJson = res.data?['user'];
    if (userJson is! Map) throw Exception('Invalid vehicle type response');
    return AuthUser.fromJson(Map<String, dynamic>.from(userJson));
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
