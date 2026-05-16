import 'dart:convert';

class StatusModel {
  final String id;
  final String content;
  final String type; // 'image', 'video', 'text'
  final String? caption;
  final DateTime createdAt;
  final DateTime expiresAt;
  final StatusUser user;
  final List<String> viewers;

  StatusModel({
    required this.id,
    required this.content,
    required this.type,
    this.caption,
    required this.createdAt,
    required this.expiresAt,
    required this.user,
    required this.viewers,
  });

  factory StatusModel.fromJson(Map<String, dynamic> json) {
    return StatusModel(
      id: json['_id'] ?? '',
      content: json['content'] ?? '',
      type: json['type'] ?? 'image',
      caption: json['caption'],
      createdAt: DateTime.parse(json['createdAt']),
      expiresAt: DateTime.parse(json['expiresAt']),
      user: StatusUser.fromJson(json['userId'] ?? {}),
      viewers: List<String>.from(json['viewers'] ?? []),
    );
  }
}

class StatusUser {
  final String id;
  final String name;
  final String? profileImage;
  final String role;

  StatusUser({
    required this.id,
    required this.name,
    this.profileImage,
    required this.role,
  });

  factory StatusUser.fromJson(Map<String, dynamic> json) {
    return StatusUser(
      id: json['_id'] ?? '',
      name: json['name'] ?? 'Unknown',
      profileImage: json['profileImage'],
      role: json['role'] ?? 'employee',
    );
  }
}

class UserStatuses {
  final StatusUser user;
  final List<StatusModel> statuses;

  UserStatuses({required this.user, required this.statuses});

  factory UserStatuses.fromJson(Map<String, dynamic> json) {
    return UserStatuses(
      user: StatusUser.fromJson(json['user'] ?? {}),
      statuses: (json['statuses'] as List? ?? [])
          .map((s) => StatusModel.fromJson(s))
          .toList(),
    );
  }
}
