class ChatConversationResponse {
  final bool success;
  final List<Conversation> conversations;
  final int totalUnread;

  ChatConversationResponse({
    required this.success,
    required this.conversations,
    required this.totalUnread,
  });

  factory ChatConversationResponse.fromJson(Map<String, dynamic> json) {
    return ChatConversationResponse(
      success: json['success'] ?? false,
      conversations:
          (json['conversations'] as List?)
              ?.map((c) => Conversation.fromJson(c))
              .toList() ??
          [],
      totalUnread: json['totalUnread'] ?? 0,
    );
  }
}

class Conversation {
  final String id;
  final List<Participant> participants;
  final LastMessage? lastMessage;
  final Map<String, int> unreadCounts;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int unreadCount;

  Conversation({
    required this.id,
    required this.participants,
    this.lastMessage,
    required this.unreadCounts,
    this.createdAt,
    this.updatedAt,
    required this.unreadCount,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['_id'] ?? '',
      participants:
          (json['participants'] as List?)
              ?.map((p) => Participant.fromJson(p))
              .toList() ??
          [],
      lastMessage: json['lastMessage'] != null
          ? LastMessage.fromJson(json['lastMessage'])
          : null,
      unreadCounts: Map<String, int>.from(json['unreadCounts'] ?? {}),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
      unreadCount: json['unreadCount'] ?? 0,
    );
  }
}

class Participant {
  final String id;
  final String name;
  final String email;
  final String fcmToken;
  final String role;
  final String? profileImage;

  Participant({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.fcmToken,
    this.profileImage,
  });

  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? '',
      fcmToken: json['fcmToken'] ?? '',
      profileImage: json['profileImage'],
    );
  }
}

class LastMessage {
  final String content;
  final String senderId;
  final String type;
  final DateTime? timestamp;

  LastMessage({
    required this.content,
    required this.senderId,
    required this.type,
    this.timestamp,
  });

  factory LastMessage.fromJson(Map<String, dynamic> json) {
    return LastMessage(
      content: json['content'] ?? '',
      senderId: json['senderId'] ?? '',
      type: json['type'] ?? 'text',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'])
          : null,
    );
  }
}
