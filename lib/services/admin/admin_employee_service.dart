import 'package:dio/dio.dart';
import '../dio_client.dart';
import '../api_constants.dart';
import '../auth_service.dart';

class AdminEmployeeService {
  final Dio _dio = DioClient().dio;
  final AuthService _authService = AuthService();

  Future<Map<String, dynamic>> getEmployees({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final token = await _authService.getAccessToken();

      final response = await _dio.get(
        ApiConstants.adminEmployees,
        queryParameters: {'page': page, 'limit': limit},
        options: Options(
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        return {
          'success': false,
          'error': response.data['error'] ?? 'Failed to load employees',
        };
      }
    } catch (e) {
      if (e is DioException) {
        return {
          'success': false,
          'error': e.response?.data['error'] ?? e.message ?? 'Network error',
        };
      }
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getEmployeeDetails(String id) async {
    try {
      final token = await _authService.getAccessToken();
      final response = await _dio.get(
        '${ApiConstants.adminEmployees}/$id',
        options: Options(
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        return {'success': false, 'error': 'Failed to load details'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
