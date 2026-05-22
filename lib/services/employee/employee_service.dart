import 'package:dio/dio.dart';
import '../dio_client.dart';
import '../api_constants.dart';
import '../../models/employee_me_response.dart';

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
      final fileName = filePath.split('/').last;
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      final response = await _dio.post(
        'api/flutter/employee/records/$recordId/upload',
        data: formData,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return {
          'success': true,
          'url': response.data['uploadedRecordUrl'],
        };
      }
      return {
        'success': false,
        'error': response.data['error'] ?? 'Upload failed',
      };
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
