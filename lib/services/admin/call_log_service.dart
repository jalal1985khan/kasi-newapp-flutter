import 'package:dio/dio.dart';
import '../dio_client.dart';
import '../api_constants.dart';
import '../auth_service.dart';
import '../../models/call_log_model.dart';

class CallLogService {
  static final Dio _dio = DioClient().dio;
  static final AuthService _authService = AuthService();

  static Future<List<CallLog>?> getAdminCallLogs({int page = 1}) async {
    try {
      final token = await _authService.getAccessToken();
      
      if (token == null) return null;

      final response = await _dio.get(
        ApiConstants.adminCallLogs,
        queryParameters: {'page': page},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['success'] == true) {
          final List logsJson = data['logs'] ?? [];
          return logsJson.map((l) => CallLog.fromJson(l)).toList();
        }
      }
      return null;
    } catch (e) {
      print('[CallLogService] Error: $e');
      return null;
    }
  }
}
