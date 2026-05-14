import 'package:flutter/material.dart';
import '../dio_client.dart';
import '../../models/chat_conversation_model.dart';
import '../../models/chat_message_model.dart';
import 'package:dio/dio.dart';
import '../api_constants.dart';

class ChatService {
  final _dio = DioClient().dio;

  Future<List<dynamic>> getPartners() async {
    try {
      final response = await _dio.get('api/chat/partners');
      if (response.data['success']) {
         return response.data['partners'];
      }
      return [];
    } catch (e) {
      debugPrint('Error getting partners: $e');
      return [];
    }
  }

  Future<String?> startConversation(String otherUserId) async {
    try {
      final response = await _dio.post('api/chat/start', data: {'otherUserId': otherUserId});
      if (response.data['success']) {
        return response.data['conversationId'];
      }
      return null;
    } catch (e) {
      debugPrint('Error starting conversation: $e');
      return null;
    }
  }

  Future<ChatConversationResponse> getConversations() async {
    try {
      final response = await _dio.get('api/chat/conversations');
      if (response.statusCode == 200) {
        return ChatConversationResponse.fromJson(response.data);
      } else {
        throw Exception('Failed to load conversations: ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw Exception(e.message ?? 'Failed to load conversations');
    }
  }

  Future<ChatMessageResponse> getMessages(String conversationId, {String? beforeId}) async {
    try {
      String url = 'api/chat/conversations/$conversationId/messages';
      if (beforeId != null) {
        url += '?before=$beforeId&limit=50';
      }
      final response = await _dio.get(url);
      if (response.statusCode == 200) {
        return ChatMessageResponse.fromJson(response.data);
      } else {
        throw Exception('Failed to load messages: ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw Exception(e.message ?? 'Failed to load messages');
    }
  }

  Future<ChatMessageResponse> sendMessage(String conversationId, String content, String type, {bool isForwarded = false, String? replyTo, String? replyContent}) async {
    try {
      final response = await _dio.post('api/chat/conversations/$conversationId/messages', data: {
        'content': content,
        'type': type,
        'isForwarded': isForwarded,
        'replyTo': replyTo,
        'replyContent': replyContent,
      });
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Wrap response data in a list to match expected Response model structure if it's a single message
        return ChatMessageResponse.fromJson({
          'success': true, 
          'messages': [response.data], 
          'hasMore': false
        });
      } else {
        throw Exception('Failed to send message: ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw Exception(e.message ?? 'Failed to send message');
    }
  }

  Future<Map<String, dynamic>> uploadMedia(String filePath) async {
    try {
      String fileName = filePath.split('/').last;
      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      final response = await _dio.post(
        ApiConstants.uploadSpaces, 
        data: formData,
        options: Options(
          headers: {
            'Content-Type': 'multipart/form-data',
          },
        ),
      );

      if (response.data['success'] == true) {
        return response.data; // { success: true, url: '...', type: 'image|audio|...' }
      } else {
        throw Exception(response.data['error'] ?? 'Upload failed');
      }
    } on DioException catch (e) {
      throw Exception(e.message ?? 'Failed to upload media');
    }
  }
  Future<void> deleteMessage(String messageId) async {
    try {
      final response = await _dio.delete('api/chat/messages/$messageId');
      if (!response.data['success']) {
        throw Exception(response.data['error'] ?? 'Failed to delete message');
      }
    } catch (e) {
      debugPrint('Error deleting message: $e');
      throw Exception('Failed to delete message');
    }
  }

  Future<void> updateMessageReaction(String messageId, String? emoji) async {
    try {
      final response = await _dio.post('api/chat/messages/$messageId/reaction', data: {
        'emoji': emoji,
      });
      if (response.data['success'] != true) {
        throw Exception(response.data['error'] ?? 'Failed to update reaction');
      }
    } catch (e) {
      debugPrint('Error updating reaction: $e');
      throw Exception('Failed to update reaction');
    }
  }
}
