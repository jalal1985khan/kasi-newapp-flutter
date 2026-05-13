import 'package:dio/dio.dart';
import '../dio_client.dart';
import '../api_constants.dart';
import '../auth_service.dart';

class AdminDashboardService {
  final Dio _dio = DioClient().dio;
  final AuthService _authService = AuthService();

  Future<Map<String, dynamic>> getDashboardData() async {
    try {
      final token = await _authService.getAccessToken();
      
      final response = await _dio.get(
        ApiConstants.adminDashboard,
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        return {
          'success': false,
          'message': response.data['message'] ?? 'Failed to load dashboard data',
        };
      }
    } catch (e) {
      if (e is DioException) {
        return {
          'success': false,
          'message': e.response?.data['message'] ?? e.message ?? 'Network error',
        };
      }
      return {
        'success': false,
        'message': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> getAccountsData({String filter = 'all'}) async {
    try {
      final token = await _authService.getAccessToken();
      
      final response = await _dio.get(
        ApiConstants.adminAccounts,
        queryParameters: {'filter': filter},
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        return {
          'success': false,
          'message': response.data['message'] ?? 'Failed to load accounts data',
        };
      }
    } catch (e) {
      if (e is DioException) {
        return {
          'success': false,
          'message': e.response?.data['message'] ?? e.message ?? 'Network error',
        };
      }
      return {
        'success': false,
        'message': e.toString(),
      };
    }
  }
}
