import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../main.dart';
import '../screens/general_pages/splash_screen.dart';
import 'api_constants.dart';

class DioClient {
  static final DioClient _instance = DioClient._internal();
  late final Dio dio;
  final _storage = const FlutterSecureStorage();
  
  String? _cachedVersion;
  String? _cachedBuild;

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
        validateStatus: (status) => status != null && status < 500 && status != 401,
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final accessToken = await _storage.read(key: 'accessToken');
          if (accessToken != null) {
            options.headers['Authorization'] = 'Bearer $accessToken';
          }

          if (_cachedVersion == null || _cachedBuild == null) {
            try {
              final packageInfo = await PackageInfo.fromPlatform();
              _cachedVersion = packageInfo.version;
              _cachedBuild = packageInfo.buildNumber;
            } catch (_) {}
          }

          if (_cachedVersion != null) {
            options.headers['x-app-version'] = _cachedVersion;
          }
          if (_cachedBuild != null) {
            options.headers['x-app-build'] = _cachedBuild;
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
                      options: Options(
                        headers: {
                          if (_cachedVersion != null) 'x-app-version': _cachedVersion,
                          if (_cachedBuild != null) 'x-app-build': _cachedBuild,
                        },
                      ),
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
                // Refresh failed: clear session
                await _storage.deleteAll();
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                
                // Redirect to Splash/Login screen
                if (navigatorKey.currentState != null) {
                  navigatorKey.currentState!.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const SplashScreen()),
                    (route) => false,
                  );
                }
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
