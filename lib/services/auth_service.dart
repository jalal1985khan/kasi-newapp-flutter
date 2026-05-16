import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/signin/signedin_user_details.dart';
import 'dio_client.dart';
import 'api_constants.dart';
import 'fcm_service.dart';
import 'chat/socket_service.dart';
import '../main.dart';
import '../screens/general_pages/splash_screen.dart';
import 'package:flutter/material.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final Dio _dio = DioClient().dio;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final FCMService _fcmService = FCMService();

  static final ValueNotifier<Map<String, dynamic>?> userNotifier = ValueNotifier(null);

  Future<void> init() async {
    final user = await getUser();
    if (user != null) {
      userNotifier.value = user;
      // Fetch fresh profile data in the background to ensure everything (like profile image) is up to date
      fetchUserProfile();
    }
  }

  String? getFullUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    // Remove leading slash if present and combine with base URL
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '${ApiConstants.baseUrl}$cleanPath';
  }

  Future<Map<String, dynamic>> login(
    String identifier,
    String password,
    String role,
  ) async {
    try {
      final response = await _dio.post(
        ApiConstants.login,
        data: {'identifier': identifier, 'password': password, 'role': role},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = SignedInUserDetails.fromJson(response.data);
        if (data.success == true) {
          return {
            'success': true,
            'role': data.user?.role,
            'isActive': data.user?.isActive,
            'data': data, // Return full data for manual storage if needed
          };
        }
      }
      return {
        'success': false,
        'message': response.data['error'] ?? 'Login failed',
      };
    } catch (e) {
      String errorMessage = 'Something went wrong';
      if (e is DioException) {
        final dynamic data = e.response?.data;
        if (data is Map<String, dynamic>) {
          errorMessage = data['error'] ?? e.message ?? errorMessage;
        } else {
          errorMessage = "Server error (non-JSON response). Status code: ${e.response?.statusCode}";
        }
      }
      return {'success': false, 'message': errorMessage};
    }
  }

  Future<void> saveLocalSession(SignedInUserDetails data) async {
    try {
      // 1. Save sensitive tokens in secure storage
      await Future.wait([
        _secureStorage.write(key: 'accessToken', value: data.accessToken),
        _secureStorage.write(key: 'refreshToken', value: data.refreshToken),
      ]);

      // 2. Save user metadata in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userJson = data.user?.toJson();
      if (userJson != null) {
        await prefs.setString('signedinuser', jsonEncode(userJson));
        // 3. Update the global notifier to trigger UI updates
        userNotifier.value = userJson;
      }

      // 4. Connect socket after session is fully established
      SocketService().connect();

      // 5. Trigger a full profile fetch to ensure we have all details (like profile image) 
      // which might be missing in the initial login response
      fetchUserProfile();
    } catch (e) {
      print('Error saving local session: $e');
    }
  }

  Future<void> registerFcmInBackground() async {
    // 1. Get the actual token from Firebase
    try {
      final realToken = await _fcmService.getToken();
      if (realToken == null) {
        print('⚠️ [FCM] Could not get real token — skipping registration');
        return;
      }
      
      // 2. Register the REAL token
      await _fcmService.syncToken(realToken);
    } catch (e) {
      print('Error registering FCM in background: $e');
    }
  }

  Future<bool> logout() async {
    try {
      final refreshToken = await _secureStorage.read(key: 'refreshToken');
      if (refreshToken != null) {
        await _dio.post(
          ApiConstants.logout,
          data: {'refreshToken': refreshToken},
        );
      }
    } catch (e) {
      // Log error but proceed to clear local data anyway
      print('Logout API error: $e');
    } finally {
      // Disconnect socket
      SocketService().disconnect();

      // Clear local storage
      await _secureStorage.deleteAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      
      // CRITICAL: Clear the global notifier so UI doesn't show stale user data
      userNotifier.value = null;
    }
    return true;
  }

  Future<String?> getAccessToken() async {
    String? token = await _secureStorage.read(key: 'accessToken');
    if (token == null) return null;

    if (isTokenExpired(token)) {
      print('Access token expired, refreshing...');
      token = await refreshAccessToken();
    }
    return token;
  }

  bool isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = (payload['exp'] as int) * 1000;
      final now = DateTime.now().millisecondsSinceEpoch;
      // Return true if expired or expiring in the next 30 seconds
      return now >= (exp - 30000);
    } catch (_) {
      return true;
    }
  }

  Future<String?> refreshAccessToken() async {
    try {
      final refreshToken = await _secureStorage.read(key: 'refreshToken');
      if (refreshToken == null) return null;

      final response = await Dio(BaseOptions(baseUrl: ApiConstants.baseUrl)).post(
        ApiConstants.refresh,
        data: {'refreshToken': refreshToken},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final newAccessToken = response.data['accessToken'];
        await _secureStorage.write(key: 'accessToken', value: newAccessToken);
        return newAccessToken;
      }
    } catch (e) {
      print('Manual token refresh failed: $e');
      // Clear session if refresh fails
      await _secureStorage.deleteAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Redirect to Splash/Login screen
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const SplashScreen()),
          (route) => false,
        );
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userStr = prefs.getString('signedinuser');
    if (userStr != null) {
      return jsonDecode(userStr);
    }
    return null;
  }

  Future<Map<String, dynamic>> fetchUserProfile() async {
    try {
      final token = await getAccessToken();
      final response = await _dio.get(
        ApiConstants.userProfile,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        final userData = response.data['user'];
        if (userData != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('signedinuser', jsonEncode(userData));
          userNotifier.value = userData;
          return {'success': true, 'user': userData};
        }
      }
      return {'success': false, 'message': 'Failed to fetch profile'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.changePassword,
        data: {
          'oldPassword': oldPassword,
          'newPassword': newPassword,
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': response.data['message'] ?? 'Password changed successfully',
        };
      }
      return {
        'success': false,
        'message': response.data['error'] ?? 'Failed to change password',
      };
    } catch (e) {
      String errorMessage = 'Failed to change password';
      if (e is DioException) {
        final dynamic data = e.response?.data;
        if (data is Map<String, dynamic>) {
          errorMessage = data['error'] ?? errorMessage;
        }
      }
      return {'success': false, 'message': errorMessage};
    }
  }

  Future<Map<String, dynamic>> updateProfile({
    String? name,
    String? email,
    String? profileImage,
  }) async {
    try {
      final token = await getAccessToken();
      final response = await _dio.patch(
        ApiConstants.userProfile,
        data: {
          if (name != null) 'name': name,
          if (email != null) 'email': email,
          if (profileImage != null) 'profileImage': profileImage,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        // Update local session data
        final prefs = await SharedPreferences.getInstance();
        final userStr = prefs.getString('signedinuser');
        if (userStr != null) {
          final userJson = jsonDecode(userStr);
          if (name != null) userJson['name'] = name;
          if (email != null) userJson['email'] = email;
          if (profileImage != null) userJson['profileImage'] = profileImage;
          await prefs.setString('signedinuser', jsonEncode(userJson));
          userNotifier.value = userJson;
        }

        return {
          'success': true,
          'message': response.data['message'] ?? 'Profile updated successfully',
          'user': response.data['user'],
        };
      }
      return {
        'success': false,
        'message': response.data['error'] ?? 'Failed to update profile',
      };
    } catch (e) {
      String errorMessage = 'Failed to update profile';
      if (e is DioException) {
        errorMessage = e.response?.data['error'] ?? errorMessage;
      }
      return {'success': false, 'message': errorMessage};
    }
  }

  Future<Map<String, dynamic>> uploadProfileImage(String filePath) async {
    try {
      final token = await getAccessToken();
      final fileName = filePath.split('/').last;
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      final response = await _dio.post(
        ApiConstants.uploadSpaces,
        data: formData,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        return {
          'success': true,
          'url': response.data['url'],
        };
      }
      return {
        'success': false,
        'message': response.data['error'] ?? 'Upload failed',
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
