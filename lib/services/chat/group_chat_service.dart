import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../dio_client.dart';
import '../api_constants.dart';
import '../auth_service.dart';

class GroupChatService {
  static final GroupChatService _instance = GroupChatService._internal();
  factory GroupChatService() => _instance;
  GroupChatService._internal();

  final Dio _dio = DioClient().dio;
  final AuthService _authService = AuthService();

  Future<Options> _authOptions() async {
    final token = await _authService.getAccessToken();
    return Options(headers: {if (token != null) 'Authorization': 'Bearer $token'});
  }

  // ─── Groups ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createGroup({
    required String name,
    required List<String> memberIds,
    String? description,
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.adminGroups,
        data: {
          'name': name,
          'memberIds': memberIds,
          'description': ?description,
        },
        options: await _authOptions(),
      );
      return response.data as Map<String, dynamic>? ?? {'success': false};
    } on DioException catch (e) {
      debugPrint('❌ createGroup: ${e.message}');
      return {'success': false, 'error': e.response?.data?['error'] ?? e.message};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getMyGroups() async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final response = await _dio.get('${ApiConstants.adminGroups}?_t=$timestamp', options: await _authOptions());
      return response.data as Map<String, dynamic>? ?? {'success': false, 'groups': []};
    } on DioException catch (e) {
      debugPrint('❌ getMyGroups: ${e.message}');
      return {'success': false, 'groups': [], 'error': e.message};
    } catch (e) {
      return {'success': false, 'groups': [], 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getGroupDetails(String groupId) async {
    try {
      final response = await _dio.get(
        '${ApiConstants.adminGroups}/$groupId',
        options: await _authOptions(),
      );
      return response.data as Map<String, dynamic>? ?? {'success': false};
    } on DioException catch (e) {
      return {'success': false, 'error': e.message};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getGroupMessages(String groupId, {String? beforeId}) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String path = '${ApiConstants.adminGroups}/$groupId/messages?_t=$timestamp';
      if (beforeId != null) path += '&beforeId=$beforeId';
      final response = await _dio.get(path, options: await _authOptions());
      return response.data as Map<String, dynamic>? ?? {'success': false, 'messages': []};
    } on DioException catch (e) {
      debugPrint('❌ getGroupMessages: ${e.message}');
      return {'success': false, 'messages': [], 'error': e.message};
    } catch (e) {
      return {'success': false, 'messages': [], 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> renameGroup(String groupId, String newName) async {
    try {
      final response = await _dio.patch(
        '${ApiConstants.adminGroups}/$groupId',
        data: {'name': newName},
        options: await _authOptions(),
      );
      return response.data as Map<String, dynamic>? ?? {'success': false};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> deleteGroup(String groupId) async {
    try {
      final response = await _dio.delete(
        '${ApiConstants.adminGroups}/$groupId',
        options: await _authOptions(),
      );
      return response.data as Map<String, dynamic>? ?? {'success': false};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ─── Members ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> addMembers(String groupId, List<String> memberIds) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.adminGroups}/$groupId/members',
        data: {'memberIds': memberIds},
        options: await _authOptions(),
      );
      return response.data as Map<String, dynamic>? ?? {'success': false};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> removeMember(String groupId, String memberId) async {
    try {
      final response = await _dio.delete(
        '${ApiConstants.adminGroups}/$groupId/members',
        data: {'memberId': memberId},
        options: await _authOptions(),
      );
      return response.data as Map<String, dynamic>? ?? {'success': false};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ─── Messages ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> deleteGroupMessage(String groupId, String messageId) async {
    try {
      final response = await _dio.delete(
        '${ApiConstants.adminGroups}/$groupId/messages/$messageId',
        options: await _authOptions(),
      );
      return response.data as Map<String, dynamic>? ?? {'success': false};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> clearGroupChat(String groupId) async {
    try {
      final response = await _dio.delete(
        '${ApiConstants.adminGroups}/$groupId/messages',
        options: await _authOptions(),
      );
      return response.data as Map<String, dynamic>? ?? {'success': false};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> updateReaction(String groupId, String messageId, String? emoji) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.adminGroups}/$groupId/messages/$messageId/reaction',
        data: {'emoji': emoji},
        options: await _authOptions(),
      );
      return response.data as Map<String, dynamic>? ?? {'success': false};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
