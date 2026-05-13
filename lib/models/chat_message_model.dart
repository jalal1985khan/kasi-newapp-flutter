class ChatMessageResponse {
  final bool success;
  final List<ChatMessage> messages;
  final bool hasMore;

  ChatMessageResponse({
    required this.success,
    required this.messages,
    required this.hasMore,
  });

  factory ChatMessageResponse.fromJson(Map<String, dynamic> json) {
    return ChatMessageResponse(
      success: json['success'] ?? false,
      messages: (json['messages'] as List?)
              ?.map((e) => ChatMessage.fromJson(e))
              .toList() ??
          [],
      hasMore: json['hasMore'] ?? false,
    );
  }
}

class ChatMessage {
  final String id;
  final String conversationId;
  final String? tenantId;
  final String senderId;
  final String receiverId;
  final String type;
  final String content;
  final String? fileName;
  final int? fileSize;
  final int? duration;
  final bool isRead;
  final DateTime? readAt;
  final List<dynamic> deletedFor;
  final DateTime createdAt;
  final String? senderName;

  ChatMessage({
    required this.id,
    required this.conversationId,
    this.tenantId,
    required this.senderId,
    required this.receiverId,
    required this.type,
    required this.content,
    this.fileName,
    this.fileSize,
    this.duration,
    required this.isRead,
    this.readAt,
    required this.deletedFor,
    required this.createdAt,
    this.senderName,
  });

  ChatMessage copyWith({
    bool? isRead,
    DateTime? readAt,
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      tenantId: tenantId,
      senderId: senderId,
      receiverId: receiverId,
      type: type,
      content: content,
      fileName: fileName,
      fileSize: fileSize,
      duration: duration,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      deletedFor: deletedFor,
      createdAt: createdAt,
      senderName: senderName,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] ?? json['_id'] ?? '',
      conversationId: json['conversationId'] ?? '',
      tenantId: json['tenantId'],
      senderId: json['senderId'] ?? '',
      receiverId: json['receiverId'] ?? '',
      type: json['type'] ?? 'text',
      content: json['content'] ?? '',
      fileName: json['fileName'],
      fileSize: json['fileSize'],
      duration: json['duration'],
      isRead: json['isRead'] ?? false,
      readAt: json['readAt'] != null ? DateTime.parse(json['readAt']) : null,
      deletedFor: json['deletedFor'] ?? [],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      senderName: json['senderName'],
    );
  }
}
