import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_constants.dart';

class DioClient {
  static final DioClient _instance = DioClient._internal();
  late final Dio dio;
  final _storage = const FlutterSecureStorage();

  factory DioClient() {
    return _instance;
  }

  DioClient._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(minutes: 20),
        receiveTimeout: const Duration(minutes: 20),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        followRedirects: true,
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final accessToken = await _storage.read(key: 'accessToken');
          if (accessToken != null) {
            options.headers['Authorization'] = 'Bearer $accessToken';
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          if (e.response?.statusCode == 401) {
            final refreshToken = await _storage.read(key: 'refreshToken');
            if (refreshToken != null) {
              try {
                final refreshResponse =
                    await Dio(BaseOptions(baseUrl: ApiConstants.baseUrl)).post(
                      ApiConstants.refresh,
                      data: {'refreshToken': refreshToken},
                    );

                if (refreshResponse.statusCode == 200 &&
                    refreshResponse.data['success'] == true) {
                  final newAccessToken = refreshResponse.data['accessToken'];
                  await _storage.write(
                    key: 'accessToken',
                    value: newAccessToken,
                  );

                  // Retry the original request with new token
                  e.requestOptions.headers['Authorization'] =
                      'Bearer $newAccessToken';
                  final response = await dio.fetch(e.requestOptions);
                  return handler.resolve(response);
                }
              } catch (refreshErr) {
                // Refresh failed, maybe redirect to login or clear data
                print('Token refresh failed: $refreshErr');
              }
            }
          }
          return handler.next(e);
        },
      ),
    );

    // Logging responses, errors, and request bodies for debugging
    dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (object) => print('DIO_LOG: $object'),
      ),
    );
  }
}
