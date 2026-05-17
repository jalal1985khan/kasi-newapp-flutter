import 'package:dio/dio.dart';
import '../models/status_model.dart';
import '../services/dio_client.dart';
import '../services/api_constants.dart';

class StatusService {
  final Dio _dio = DioClient().dio;

  Future<List<UserStatuses>> getStatuses() async {
    try {
      final response = await _dio.get(ApiConstants.statuses);
      if (response.data['success'] == true) {
        return (response.data['statuses'] as List)
            .map((s) => UserStatuses.fromJson(s))
            .toList();
      }
      return [];
    } catch (e) {
      print('Error fetching statuses: $e');
      return [];
    }
  }

  Future<bool> createStatus({
    required String content,
    required String type,
    String? caption,
  }) async {
    try {
      final response = await _dio.post(ApiConstants.statuses, data: {
        'content': content,
        'type': type,
        'caption': caption,
      });
      return response.data['success'] == true;
    } catch (e) {
      print('Error creating status: $e');
      return false;
    }
  }

  Future<bool> viewStatus(String statusId) async {
    try {
      final response = await _dio.post('${ApiConstants.statuses}/$statusId/view');
      return response.data['success'] == true;
    } catch (e) {
      print('Error viewing status: $e');
      return false;
    }
  }

  Future<bool> deleteStatus(String statusId) async {
    try {
      final response = await _dio.delete('${ApiConstants.statuses}/$statusId');
      return response.data['success'] == true;
    } catch (e) {
      print('Error deleting status: $e');
      return false;
    }
  }
}
