import 'package:dio/dio.dart';
import '../dio_client.dart';
import '../api_constants.dart';
import '../auth_service.dart';

class GroupChatService {
  final Dio _dio = DioClient().dio;
  final AuthService _authService = AuthService();

  /// Create a new group
  Future<Map<String, dynamic>> createGroup({
    required String name,
    required List<String> memberIds,
    String? description,
  }) async {
    try {
      final token = await _authService.getAccessToken();
      
      final response = await _dio.post(
        ApiConstants.adminGroups,
        data: {
          'name': name,
          'memberIds': memberIds,
          if (description != null) 'description': description,
        },
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data;
      } else {
        return {
          'success': false,
          'error': response.data['error'] ?? 'Failed to create group',
        };
      }
    } catch (e) {
      if (e is DioException) {
        return {
          'success': false,
          'error': e.response?.data['error'] ?? e.message ?? 'Network error',
        };
      }
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// List all groups I am a member of
  Future<Map<String, dynamic>> getMyGroups() async {
    try {
      final token = await _authService.getAccessToken();
      
      final response = await _dio.get(
        ApiConstants.adminGroups,
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        return {
          'success': false,
          'error': response.data['error'] ?? 'Failed to fetch groups',
        };
      }
    } catch (e) {
      if (e is DioException) {
        return {
          'success': false,
          'error': e.response?.data['error'] ?? e.message ?? 'Network error',
        };
      }
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get messages for a group
  Future<Map<String, dynamic>> getGroupMessages(String groupId) async {
     try {
      final token = await _authService.getAccessToken();
      
      final response = await _dio.get(
        '${ApiConstants.adminGroups}/$groupId/messages',
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        return {
          'success': false,
          'error': response.data['error'] ?? 'Failed to load group messages',
        };
      }
    } catch (e) {
      if (e is DioException) {
        return {
          'success': false,
          'error': e.response?.data['error'] ?? e.message ?? 'Network error',
        };
      }
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get group details
  Future<Map<String, dynamic>> getGroupDetails(String groupId) async {
    try {
      final token = await _authService.getAccessToken();
      final response = await _dio.get(
        '${ApiConstants.adminGroups}/$groupId',
        options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}),
      );
      return response.data;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Rename group
  Future<Map<String, dynamic>> renameGroup(String groupId, String newName) async {
    try {
      final token = await _authService.getAccessToken();
      final response = await _dio.patch(
        '${ApiConstants.adminGroups}/$groupId',
        data: {'name': newName},
        options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}),
      );
      return response.data;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Delete group
  Future<Map<String, dynamic>> deleteGroup(String groupId) async {
    try {
      final token = await _authService.getAccessToken();
      final response = await _dio.delete(
        '${ApiConstants.adminGroups}/$groupId',
        options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}),
      );
      return response.data;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Add members to group
  Future<Map<String, dynamic>> addMembers(String groupId, List<String> memberIds) async {
    try {
      final token = await _authService.getAccessToken();
      final response = await _dio.post(
        '${ApiConstants.adminGroups}/$groupId/members',
        data: {'memberIds': memberIds},
        options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}),
      );
      return response.data;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Remove member from group
  Future<Map<String, dynamic>> removeMember(String groupId, String memberId) async {
    try {
      final token = await _authService.getAccessToken();
      final response = await _dio.delete(
        '${ApiConstants.adminGroups}/$groupId/members',
        data: {'memberId': memberId},
        options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}),
      );
      return response.data;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Soft-delete group message
  Future<Map<String, dynamic>> deleteGroupMessage(String groupId, String messageId) async {
    try {
      final token = await _authService.getAccessToken();
      final response = await _dio.delete(
        '${ApiConstants.adminGroups}/$groupId/messages/$messageId',
        options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}),
      );
      return response.data;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Clear all messages in a group
  Future<Map<String, dynamic>> clearGroupChat(String groupId) async {
    try {
      final token = await _authService.getAccessToken();
      final response = await _dio.delete(
        '${ApiConstants.adminGroups}/$groupId/messages',
        options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}),
      );
      return response.data;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
