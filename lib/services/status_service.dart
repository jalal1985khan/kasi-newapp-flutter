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
    String? originalUrl,
  }) async {
    try {
      final response = await _dio.post(ApiConstants.statuses, data: {
        'content': content,
        'type': type,
        'caption': caption,
        if (originalUrl != null) 'originalUrl': originalUrl,
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

  Future<Map<String, dynamic>> uploadStatusMedia(String filePath) async {
    try {
      final token = await DioClient().getAccessToken();
      final fileName = filePath.split('/').last;
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      final response = await _dio.post(
        ApiConstants.uploadCloudinary,
        data: formData,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return {
          'success': true,
          'url': response.data['url'],
          'originalUrl': response.data['originalUrl'],
        };
      }
      return {
        'success': false,
        'message': response.data['error'] ?? 'Upload failed',
      };
    } catch (e) {
      print('Error uploading status media: $e');
      return {
        'success': false,
        'message': e.toString(),
      };
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
