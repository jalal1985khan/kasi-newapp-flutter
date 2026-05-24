import 'dart:convert';

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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'participants': jsonEncode(participants.map((p) => p.toMap()).toList()),
      'lastMessage': lastMessage != null ? jsonEncode(lastMessage!.toMap()) : null,
      'unreadCounts': jsonEncode(unreadCounts),
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'unreadCount': unreadCount,
    };
  }

  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      id: map['id'] ?? '',
      participants: map['participants'] != null 
          ? (jsonDecode(map['participants']) as List).map((p) => Participant.fromMap(p)).toList()
          : [],
      lastMessage: map['lastMessage'] != null 
          ? LastMessage.fromMap(jsonDecode(map['lastMessage']))
          : null,
      unreadCounts: map['unreadCounts'] != null
          ? Map<String, int>.from(jsonDecode(map['unreadCounts']))
          : {},
      createdAt: map['createdAt'] != null ? DateTime.parse(map['createdAt']) : null,
      updatedAt: map['updatedAt'] != null ? DateTime.parse(map['updatedAt']) : null,
      unreadCount: map['unreadCount'] ?? 0,
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
      profileImage: json['profileImage'] ?? json['profile_image'] ?? json['avatar'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'role': role,
      'fcmToken': fcmToken,
      'profileImage': profileImage,
    };
  }

  factory Participant.fromMap(Map<String, dynamic> map) {
    return Participant(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      role: map['role'] ?? '',
      fcmToken: map['fcmToken'] ?? '',
      profileImage: map['profileImage'],
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

  Map<String, dynamic> toMap() {
    return {
      'content': content,
      'senderId': senderId,
      'type': type,
      'timestamp': timestamp?.toIso8601String(),
    };
  }

  factory LastMessage.fromMap(Map<String, dynamic> map) {
    return LastMessage(
      content: map['content'] ?? '',
      senderId: map['senderId'] ?? '',
      type: map['type'] ?? 'text',
      timestamp: map['timestamp'] != null ? DateTime.parse(map['timestamp']) : null,
    );
  }
}
