import 'package:dio/dio.dart';
import '../dio_client.dart';
import '../api_constants.dart';
import '../../models/employee_me_response.dart';
import '../auth_service.dart';

class EmployeeService {
  final _dio = DioClient().dio;

  Future<EmployeeMeResponse> getEmployeeMe({int page = 1, int limit = 10}) async {
    try {
      final response = await _dio.get(
        ApiConstants.employeeMe,
        queryParameters: {'page': page, 'limit': limit},
      );
      if (response.statusCode == 200) {
        return EmployeeMeResponse.fromJson(response.data);
      } else {
        throw Exception('Failed to load employee data');
      }
    } on DioException catch (e) {
      throw Exception(e.message ?? 'Unknown error occurred');
    }
  }

  Future<Map<String, dynamic>> uploadBatchRecordImage(String recordId, String filePath) async {
    try {
      final token = await AuthService().getAccessToken();
      final fileName = filePath.split('/').last;
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      final response = await _dio.post(
        'api/flutter/employee/records/$recordId/upload',
        data: formData,
        options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200 && response.data != null && response.data is Map && response.data['success'] == true) {
        return {
          'success': true,
          'url': response.data['uploadedRecordUrl'],
        };
      }
      return {
        'success': false,
        'error': (response.data is Map) ? (response.data['error'] ?? 'Upload failed') : 'Server error. Please try again.',
      };
    } catch (e) {
      if (e is DioException) {
        return {
          'success': false,
          'error': (e.response?.data is Map) ? (e.response?.data['error'] ?? e.message) : (e.message ?? 'Network error'),
        };
      }
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}
