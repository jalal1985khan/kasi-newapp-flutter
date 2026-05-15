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
  final String? reaction;
  final String? replyToContent;
  final String? replyToSenderName;
  final String? replyTo;
  final bool isForwarded;

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
    this.reaction,
    this.replyToContent,
    this.replyToSenderName,
    this.replyTo,
    this.isForwarded = false,
  });

  ChatMessage copyWith({
    String? id,
    String? conversationId,
    String? tenantId,
    String? senderId,
    String? receiverId,
    String? type,
    String? content,
    String? fileName,
    int? fileSize,
    int? duration,
    bool? isRead,
    DateTime? readAt,
    List<dynamic>? deletedFor,
    DateTime? createdAt,
    String? senderName,
    String? reaction,
    String? replyToContent,
    String? replyToSenderName,
    String? replyTo,
    bool? isForwarded,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      tenantId: tenantId ?? this.tenantId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      type: type ?? this.type,
      content: content ?? this.content,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      duration: duration ?? this.duration,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      deletedFor: deletedFor ?? this.deletedFor,
      createdAt: createdAt ?? this.createdAt,
      senderName: senderName ?? this.senderName,
      reaction: reaction ?? this.reaction,
      replyToContent: replyToContent ?? this.replyToContent,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      replyTo: replyTo ?? this.replyTo,
      isForwarded: isForwarded ?? this.isForwarded,
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
      reaction: json['reaction'],
      replyToContent: json['replyToContent'] ?? json['reply_to_content'],
      replyToSenderName: json['replyToSenderName'] ?? json['reply_to_sender_name'],
      replyTo: json['replyTo'] ?? json['reply_to'],
      isForwarded: json['isForwarded'] ?? json['is_forwarded'] ?? false,
    );
  }
}
