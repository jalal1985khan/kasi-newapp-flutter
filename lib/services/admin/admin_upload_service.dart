import 'package:dio/dio.dart';
import '../dio_client.dart';
import '../api_constants.dart';
import '../auth_service.dart';

class AdminUploadService {
  final Dio _dio = DioClient().dio;
  final AuthService _authService = AuthService();

  Future<Map<String, dynamic>> uploadExcel(String filePath) async {
    try {
      final token = await _authService.getAccessToken();
      
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          filePath,
          filename: filePath.split('/').last,
        ),
      });

      final response = await _dio.post(
        ApiConstants.adminBulkUpload,
        data: formData,
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data;
      } else {
        return {
          'success': false,
          'error': response.data['error'] ?? 'Upload failed',
        };
      }
    } catch (e) {
      if (e is DioException) {
        return {
          'success': false,
          'error': e.response?.data['error'] ?? e.message ?? 'Network error',
        };
      }
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}
