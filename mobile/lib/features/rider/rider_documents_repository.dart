import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import '../../models/auth_user.dart';
import '../../models/rider_document.dart';
import '../auth/auth_repository.dart';

class RiderDocumentsRepository {
  RiderDocumentsRepository(this._api);

  final ApiClient _api;

  Future<RiderDocumentsState> fetchDocuments() async {
    final res = await _api.dio.get<Map<String, dynamic>>('/api/rider/documents');
    return RiderDocumentsState.fromJson(
      Map<String, dynamic>.from(res.data ?? {}),
    );
  }

  Future<AuthResult> uploadDocument({
    required String docType,
    required String filePath,
  }) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        filePath,
        filename: _uploadFileName(filePath),
      ),
    });
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/rider/documents/$docType/upload',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    return _parseUploadResponse(res.data);
  }

  static String _uploadFileName(String filePath) {
    final name = filePath.split(RegExp(r'[/\\]')).last.trim();
    if (name.isEmpty) return 'photo.jpg';
    if (!name.contains('.')) return '$name.jpg';
    return name;
  }

  Future<AuthResult> submitForReview() async {
    final res = await _api.dio.post<Map<String, dynamic>>(
      '/api/rider/documents/submit',
    );
    return _parseUploadResponse(res.data);
  }

  AuthResult _parseUploadResponse(Map<String, dynamic>? data) {
    if (data == null) throw Exception('Empty response');
    final token = data['token']?.toString();
    final userJson = data['user'];
    if (token == null || userJson is! Map) {
      throw Exception('Invalid response');
    }
    return AuthResult(
      token: token,
      user: AuthUser.fromJson(Map<String, dynamic>.from(userJson)),
    );
  }

  static String errorMessage(Object err) {
    if (err is DioException) {
      return ApiClient.messageFromDio(err, 'Document request failed');
    }
    if (err is Exception) return err.toString().replaceFirst('Exception: ', '');
    return err.toString();
  }
}
