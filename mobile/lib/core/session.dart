import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../features/auth/auth_repository.dart';
import '../models/auth_user.dart';
import 'api_client.dart';
import 'socket_service.dart';

const _kToken = 'bytzgo_token';
const _kUser = 'bytzgo_user';

/// Holds JWT + user profile; persists across app restarts.
class Session extends ChangeNotifier {
  Session(this._api, this._socket);

  final ApiClient _api;
  final SocketService _socket;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _token;
  AuthUser? _user;
  bool _restoring = true;

  /// Set from [BytzGoApp] to refresh push routing when auth changes.
  Future<void> Function()? onAuthChanged;

  String? get token => _token;
  AuthUser? get user => _user;
  bool get isAuthenticated => _token != null && _user != null;
  bool get isRestoring => _restoring;

  /// Issues a slim JWT from the server (fixes HTTP 431 from legacy bloated tokens).
  Future<bool> refreshAuthFromServer() async {
    if (!isAuthenticated) return false;
    try {
      final result = await AuthRepository(_api).refreshSession();
      await setSession(token: result.token, user: result.user);
      return true;
    } catch (e) {
      debugPrint('Session refresh failed: $e');
      if (e is DioException && ApiClient.isHeaderTooLargeError(e)) {
        await clear();
      }
      return false;
    }
  }

  Future<void> restore() async {
    _restoring = true;
    notifyListeners();
    try {
      final token = (await _storage.read(key: _kToken))?.trim();
      final userJson = await _storage.read(key: _kUser);
      if (token != null && token.isNotEmpty && userJson != null) {
        if (ApiClient.isOversizedAuthToken(token)) {
          debugPrint('Session: clearing oversized auth token (${token.length} chars)');
          await clear();
          return;
        }
        _token = token;
        _user = AuthUser.fromJson(
          jsonDecode(userJson) as Map<String, dynamic>,
        );
        _api.setToken(token);
        await _connectSocket();
        if (onAuthChanged != null) await onAuthChanged!();
      }
    } catch (e) {
      debugPrint('Session restore failed: $e');
      await clear();
    } finally {
      _restoring = false;
      notifyListeners();
    }
  }

  Future<void> applyAuthResult({required String token, required AuthUser user}) async {
    await setSession(token: token, user: user);
  }

  Future<void> setSession({
    required String token,
    required AuthUser user,
  }) async {
    if (ApiClient.isOversizedAuthToken(token)) {
      throw StateError('Auth token is too large — sign in again after updating the app.');
    }
    _token = token;
    _user = user;
    _api.setToken(token);
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kUser, value: jsonEncode(user.toJson()));
    await _connectSocket();
    if (onAuthChanged != null) await onAuthChanged!();
    notifyListeners();
  }

  Future<void> clear() async {
    _token = null;
    _user = null;
    _api.setToken(null);
    _socket.disconnect();
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kUser);
    if (onAuthChanged != null) await onAuthChanged!();
    notifyListeners();
  }

  void patchUser(AuthUser user) {
    _user = user;
    _storage.write(key: _kUser, value: jsonEncode(user.toJson()));
    notifyListeners();
  }

  void patchBalance(double balance) {
    if (_user == null) return;
    patchUser(_user!.copyWith(balance: balance));
  }

  Future<void> _connectSocket() async {
    final id = _user?.id;
    if (id == null) return;
    await _socket.connect(userId: id, token: _token);
  }
}
