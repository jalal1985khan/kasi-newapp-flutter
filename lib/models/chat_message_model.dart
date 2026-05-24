enum MessageUploadStatus { pending, uploading, success, error }

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
  final String? senderRole;
  final String? reaction;
  final String? replyToContent;
  final String? replyToSenderName;
  final String? replyTo;
  final bool isForwarded;
  final String? caption;
  final String? senderProfileImage;
  
  // Local-only fields for background upload
  final double uploadProgress;
  final MessageUploadStatus uploadStatus;
  final String? localPath;

  final String? previewUrl;

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
    this.senderRole,
    this.reaction,
    this.replyToContent,
    this.replyToSenderName,
    this.replyTo,
    this.isForwarded = false,
    this.caption,
    this.senderProfileImage,
    this.uploadProgress = 1.0,
    this.uploadStatus = MessageUploadStatus.success,
    this.localPath,
    this.previewUrl,
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
    String? senderRole,
    String? reaction,
    String? replyToContent,
    String? replyToSenderName,
    String? replyTo,
    bool? isForwarded,
    String? caption,
    String? senderProfileImage,
    double? uploadProgress,
    MessageUploadStatus? uploadStatus,
    String? localPath,
    String? previewUrl,
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
      senderRole: senderRole ?? this.senderRole,
      reaction: reaction ?? this.reaction,
      replyToContent: replyToContent ?? this.replyToContent,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      replyTo: replyTo ?? this.replyTo,
      isForwarded: isForwarded ?? this.isForwarded,
      caption: caption ?? this.caption,
      senderProfileImage: senderProfileImage ?? this.senderProfileImage,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      uploadStatus: uploadStatus ?? this.uploadStatus,
      localPath: localPath ?? this.localPath,
      previewUrl: previewUrl ?? this.previewUrl,
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
      senderRole: json['senderRole'],
      reaction: json['reaction'],
      replyToContent: json['replyToContent'] ?? json['reply_to_content'],
      replyToSenderName: json['replyToSenderName'] ?? json['reply_to_sender_name'],
      replyTo: json['replyTo'] ?? json['reply_to'],
      isForwarded: json['isForwarded'] ?? json['is_forwarded'] ?? false,
      caption: json['caption'],
      senderProfileImage: json['senderProfileImage'] ?? json['sender_profile_image'] ?? json['sender_avatar'],
      previewUrl: json['previewUrl'] ?? json['preview_url'],
      uploadProgress: 1.0,
      uploadStatus: MessageUploadStatus.success,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversationId': conversationId,
      'tenantId': tenantId,
      'senderId': senderId,
      'receiverId': receiverId,
      'type': type,
      'content': content,
      'fileName': fileName,
      'fileSize': fileSize,
      'duration': duration,
      'isRead': isRead ? 1 : 0,
      'readAt': readAt?.toIso8601String(),
      // 'deletedFor' is ignored or stored as string array
      'deletedFor': deletedFor.toString(),
      'createdAt': createdAt.toIso8601String(),
      'senderName': senderName,
      'senderRole': senderRole,
      'reaction': reaction,
      'replyToContent': replyToContent,
      'replyToSenderName': replyToSenderName,
      'replyTo': replyTo,
      'isForwarded': isForwarded ? 1 : 0,
      'caption': caption,
      'senderProfileImage': senderProfileImage,
      'uploadProgress': uploadProgress,
      'uploadStatus': uploadStatus.toString(),
      'localPath': localPath,
      'previewUrl': previewUrl,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] ?? '',
      conversationId: map['conversationId'] ?? '',
      tenantId: map['tenantId'],
      senderId: map['senderId'] ?? '',
      receiverId: map['receiverId'] ?? '',
      type: map['type'] ?? 'text',
      content: map['content'] ?? '',
      fileName: map['fileName'],
      fileSize: map['fileSize'],
      duration: map['duration'],
      isRead: map['isRead'] == 1,
      readAt: map['readAt'] != null ? DateTime.parse(map['readAt']) : null,
      deletedFor: [], // Parsed back empty or ignore
      createdAt: map['createdAt'] != null ? DateTime.parse(map['createdAt']) : DateTime.now(),
      senderName: map['senderName'],
      senderRole: map['senderRole'],
      reaction: map['reaction'],
      replyToContent: map['replyToContent'],
      replyToSenderName: map['replyToSenderName'],
      replyTo: map['replyTo'],
      isForwarded: map['isForwarded'] == 1,
      caption: map['caption'],
      senderProfileImage: map['senderProfileImage'],
      uploadProgress: map['uploadProgress'] ?? 1.0,
      uploadStatus: map['uploadStatus'] != null 
          ? MessageUploadStatus.values.firstWhere((e) => e.toString() == map['uploadStatus'], orElse: () => MessageUploadStatus.success)
          : MessageUploadStatus.success,
      localPath: map['localPath'],
      previewUrl: map['previewUrl'],
    );
  }
}
