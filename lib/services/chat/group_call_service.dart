import 'package:dio/dio.dart';
import '../dio_client.dart';
import '../api_constants.dart';
import '../auth_service.dart';

/// Service for group voice call API operations.
/// Uses the same Twilio token pattern as CallService but
/// targeting the /api/group-call/* endpoints.
class GroupCallService {
  final Dio _dio = DioClient().dio;
  final AuthService _authService = AuthService();

  /// Step 1 (Host): Initiate a group call.
  /// Creates a Twilio group room and returns a token for the host.
  Future<Map<String, dynamic>> getGroupCallToken(String groupId) async {
    try {
      final token = await _authService.getAccessToken();
      final response = await _dio.post(
        ApiConstants.groupCallToken,
        data: {'groupId': groupId},
        options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200) {
        return {
          'success':      true,
          'callId':       response.data['callId'],
          'roomName':     response.data['roomName'],
          'token':        response.data['token'],
          'limitSeconds': response.data['limitSeconds'],
          'groupName':    response.data['groupName'],
          'memberCount':  response.data['memberCount'],
        };
      }
      return {'success': false, 'message': response.data['error'] ?? 'Failed to start group call'};
    } catch (e) {
      if (e is DioException) {
        return {'success': false, 'message': e.response?.data['error'] ?? e.message ?? 'Network error'};
      }
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Step 2 (Member): Accept an incoming group call.
  /// Gets a Twilio token to connect to the existing room.
  Future<Map<String, dynamic>> joinGroupCall(String callId) async {
    try {
      final token = await _authService.getAccessToken();
      final response = await _dio.post(
        ApiConstants.groupCallJoin,
        data: {'callId': callId},
        options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200) {
        return {
          'success':      true,
          'roomName':     response.data['roomName'],
          'token':        response.data['token'],
          'limitSeconds': response.data['limitSeconds'],
          'callId':       response.data['callId'],
        };
      }
      return {'success': false, 'message': response.data['error'] ?? 'Failed to join group call'};
    } catch (e) {
      if (e is DioException) {
        return {'success': false, 'message': e.response?.data['error'] ?? e.message ?? 'Network error'};
      }
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Leave or end a group call.
  Future<Map<String, dynamic>> endGroupCall(String callId, {bool decline = false}) async {
    try {
      final token = await _authService.getAccessToken();
      final response = await _dio.post(
        ApiConstants.groupCallEnd,
        data: {'callId': callId, 'decline': decline},
        options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'callEnded': response.data['callEnded']};
      }
      return {'success': false};
    } catch (_) {
      return {'success': false};
    }
  }
}
