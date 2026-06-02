
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
    try {
      return StatusModel(
        id: json['_id'] ?? '',
        content: json['content'] ?? '',
        type: json['type'] ?? 'image',
        caption: json['caption'],
        createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
        expiresAt: json['expiresAt'] != null ? DateTime.parse(json['expiresAt']) : DateTime.now(),
        user: StatusUser.fromJson(json['userId'] ?? {}),
        viewers: (json['viewers'] as List? ?? [])
            .map((v) => v.toString())
            .toList(),
      );
    } catch (e, stack) {
      print('❌ [StatusModel] JSON parsing error: $e\n$stack\nJSON: $json');
      rethrow;
    }
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
    try {
      return StatusUser(
        id: json['_id'] ?? '',
        name: json['name'] ?? 'Unknown',
        profileImage: json['profileImage'],
        role: json['role'] ?? 'employee',
      );
    } catch (e, stack) {
      print('❌ [StatusUser] JSON parsing error: $e\n$stack\nJSON: $json');
      rethrow;
    }
  }
}

class UserStatuses {
  final StatusUser user;
  final List<StatusModel> statuses;

  UserStatuses({required this.user, required this.statuses});

  factory UserStatuses.fromJson(Map<String, dynamic> json) {
    try {
      return UserStatuses(
        user: StatusUser.fromJson(json['user'] ?? {}),
        statuses: (json['statuses'] as List? ?? [])
            .map((s) => StatusModel.fromJson(s))
            .toList(),
      );
    } catch (e, stack) {
      print('❌ [UserStatuses] JSON parsing error: $e\n$stack\nJSON: $json');
      rethrow;
    }
  }
}
