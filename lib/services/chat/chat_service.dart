import 'dart:io';
import 'package:flutter/material.dart';
import '../dio_client.dart';
import '../../models/chat_conversation_model.dart';
import '../../models/chat_message_model.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import '../api_constants.dart';
import '../auth_service.dart';

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

  Future<Map<String, dynamic>> uploadMedia(String filePath, {void Function(int, int)? onSendProgress}) async {
    try {
      final token = await AuthService().getAccessToken();
      final fileName = filePath.split('/').last;
      
      String mimeType = 'application/octet-stream';
      if (fileName.toLowerCase().endsWith('.pdf')) {
        mimeType = 'application/pdf';
      } else if (fileName.toLowerCase().endsWith('.doc') || fileName.toLowerCase().endsWith('.docx')) {
        mimeType = 'application/msword';
      } else if (fileName.toLowerCase().endsWith('.png')) {
        mimeType = 'image/png';
      } else if (fileName.toLowerCase().endsWith('.jpg') || fileName.toLowerCase().endsWith('.jpeg')) {
        mimeType = 'image/jpeg';
      } else if (fileName.toLowerCase().endsWith('.mp4')) {
        mimeType = 'video/mp4';
      } else if (fileName.toLowerCase().endsWith('.mov')) {
        mimeType = 'video/quicktime';
      } else if (fileName.toLowerCase().endsWith('.m4a')) {
        mimeType = 'audio/mp4';
      }

      // Step 1: Get Presigned URL
      final presignedRes = await _dio.post(
        ApiConstants.uploadPresigned,
        data: {'fileName': fileName, 'contentType': mimeType},
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (presignedRes.statusCode != 200 || presignedRes.data['success'] != true) {
        throw Exception(presignedRes.data['error'] ?? 'Failed to get upload URL');
      }

      final putUrl = presignedRes.data['putUrl'];
      final spacesUrl = presignedRes.data['spacesUrl'];

      // Step 2: Upload File directly to Spaces
      final file = File(filePath);
      final fileBytes = await file.readAsBytes();
      
      // Use standard Dio for the direct PUT to avoid base url intercepts
      final directDio = Dio();
      final uploadRes = await directDio.put(
        putUrl,
        data: fileBytes,
        options: Options(
          headers: {
            Headers.contentTypeHeader: mimeType,
            Headers.contentLengthHeader: fileBytes.length.toString(),
            'x-amz-acl': 'public-read',
          },
          sendTimeout: const Duration(minutes: 60), // generous timeout for large files
          receiveTimeout: const Duration(minutes: 60),
        ),
        onSendProgress: onSendProgress,
      );
      
      if (uploadRes.statusCode != 200 && uploadRes.statusCode != 201) {
         throw Exception('Direct upload to Spaces failed with status ${uploadRes.statusCode}');
      }

      // Step 3: Finalize Upload (trigger Cloudinary proxy)
      final finalizeRes = await _dio.post(
        ApiConstants.uploadFinalize,
        data: {
          'spacesUrl': spacesUrl,
          'fileName': fileName,
          'contentType': mimeType,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );

      if (finalizeRes.statusCode == 200 && finalizeRes.data['success'] == true) {
        return {
          'success': true,
          'url': finalizeRes.data['url'],
          'originalUrl': finalizeRes.data['originalUrl'],
        };
      } else {
        throw Exception(finalizeRes.data['error'] ?? 'Upload finalization failed');
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
  Future<int> getTotalUnreadCount() async {
    try {
      final response = await _dio.get('api/chat/unread-count');
      if (response.data['success']) {
        return response.data['totalUnread'] ?? 0;
      }
      return 0;
    } catch (e) {
      debugPrint('Error getting total unread count: $e');
      return 0;
    }
  }
}
