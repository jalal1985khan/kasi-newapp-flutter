import 'package:dio/dio.dart';
import '../dio_client.dart';
import '../api_constants.dart';

class FcmService {
  final Dio _dio = DioClient().dio;

  Future<void> registerFcmToken(String fcmToken) async {
    try {
      final response = await _dio.post(
        ApiConstants.registerFcm,
        data: {'fcmToken': fcmToken},
      );

      if (response.statusCode == 200) {
        print('FCM token registered successfully');
      } else {
        print('Failed to register FCM token: ${response.data}');
      }
    } catch (e) {
      print('Error registering FCM token: $e');
    }
  }
}
