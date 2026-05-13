import 'package:dio/dio.dart';
import '../dio_client.dart';
import '../auth_service.dart';

class CallService {
  final Dio _dio = DioClient().dio;
  final AuthService _authService = AuthService();

  Future<Map<String, dynamic>> getCallToken(String receiverId) async {
    try {
      final token = await _authService.getAccessToken();
      final response = await _dio.post(
        'api/flutter/call/token',
        data: {'receiverId': receiverId},
        options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200) {
        return {
          'success': true,
          'callId':       response.data['callId'],
          'roomName':     response.data['roomName'],
          'token':        response.data['token'],
          'limitSeconds': response.data['limitSeconds'],
        };
      }
      return {'success': false, 'message': response.data['error'] ?? 'Failed to get call token'};
    } catch (e) {
      if (e is DioException) {
        return {'success': false, 'message': e.response?.data['error'] ?? e.message ?? 'Network error'};
      }
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Receiver calls this after accepting — gets their Twilio token + roomName.
  Future<Map<String, dynamic>> joinCall(String callId) async {
    try {
      final token = await _authService.getAccessToken();
      final response = await _dio.post(
        'api/flutter/call/join',
        data: {'callId': callId},
        options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200) {
        return {
          'success':      true,
          'roomName':     response.data['roomName'],
          'token':        response.data['token'],
          'limitSeconds': response.data['limitSeconds'],
        };
      }
      return {'success': false, 'message': response.data['error'] ?? 'Failed to join call'};
    } catch (e) {
      if (e is DioException) {
        return {'success': false, 'message': e.response?.data['error'] ?? e.message ?? 'Network error'};
      }
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Returns STUN/TURN ICE servers from Twilio NTS (or Google fallback).
  Future<List<Map<String, dynamic>>> getIceServers() async {
    try {
      final token = await _authService.getAccessToken();
      final response = await _dio.get(
        'api/flutter/call/ice',
        options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200 && response.data['iceServers'] != null) {
        return List<Map<String, dynamic>>.from(response.data['iceServers']);
      }
    } catch (_) {}
    // Fallback to Google STUN
    return [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];
  }
}
